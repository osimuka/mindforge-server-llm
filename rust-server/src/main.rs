use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use anyhow::{anyhow, Result};
use llama_cpp::{LlamaModel, LlamaParams};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{Mutex, Semaphore};

// Configure the maximum number of concurrent inference requests
const MAX_CONCURRENT_INFERENCES: usize = 32;

#[derive(Deserialize, Serialize, Clone)]
struct Message {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    #[serde(default = "default_temperature")]
    temperature: f32,
    #[serde(default = "default_max_tokens")]
    max_tokens: u32,
}

fn default_temperature() -> f32 {
    0.7
}

fn default_max_tokens() -> u32 {
    100
}

#[derive(Serialize)]
struct ChatResponse {
    id: String,
    object: String,
    created: u64,
    model: String,
    choices: Vec<Choice>,
    usage: Usage,
}

#[derive(Serialize)]
struct Choice {
    index: u32,
    message: Message,
    finish_reason: String,
}

#[derive(Serialize)]
struct Usage {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
}

struct AppState {
    model: Arc<Mutex<Option<LlamaModel>>>,
    inference_semaphore: Semaphore,
    allow_placeholder: bool,
}

fn read_prompt_file(prompt_name: &str) -> Result<String> {
    let prompt_path = format!("/prompts/{}.txt", prompt_name);
    if !Path::new(&prompt_path).exists() {
        return Err(anyhow!("Prompt template {} not found", prompt_name));
    }
    fs::read_to_string(&prompt_path).map_err(|e| anyhow!("Failed to read prompt file: {}", e))
}

async fn root() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({ "status": "ok" }))
}

async fn health() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "upstream": true
    }))
}

async fn list_prompts() -> impl Responder {
    let paths = match fs::read_dir("/prompts") {
        Ok(paths) => paths,
        Err(_) => {
            return HttpResponse::InternalServerError()
                .json(serde_json::json!({"error": "Failed to read prompts directory"}))
        }
    };

    let mut prompts = Vec::new();
    for path in paths {
        if let Ok(entry) = path {
            if let Some(name) = entry.file_name().to_str() {
                if name.ends_with(".txt") {
                    prompts.push(name.replace(".txt", ""));
                }
            }
        }
    }

    HttpResponse::Ok().json(prompts)
}

#[derive(Deserialize)]
struct PromptQuery {
    prompt: Option<String>,
}

async fn generate(
    request: web::Json<ChatRequest>,
    prompt_query: Option<web::Query<PromptQuery>>,
    state: web::Data<Arc<AppState>>,
) -> impl Responder {
    let _permit = match state.inference_semaphore.acquire().await {
        Ok(permit) => permit,
        Err(_) => {
            return HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Server is currently overloaded"}))
        }
    };

    let start_time = Instant::now();

    // Get system prompt if requested
    let mut system_prompt = String::new();
    if let Some(query) = prompt_query {
        if let Some(prompt_name) = &query.prompt {
            match read_prompt_file(prompt_name) {
                Ok(content) => system_prompt = content,
                Err(e) => {
                    return HttpResponse::NotFound()
                        .json(serde_json::json!({"error": format!("{}", e)}))
                }
            }
        }
    }

    // Build the prompt
    let mut messages = request.messages.clone();
    if !system_prompt.is_empty() {
        messages.insert(
            0,
            Message {
                role: "system".to_string(),
                content: system_prompt,
            },
        );
    }

    let formatted_prompt = format_messages_for_llama(&messages);
    // If model is not loaded and placeholders are not allowed, return 503 early with a clear message.
    {
        let guard = state.model.lock().await;
        if guard.is_none() && !state.allow_placeholder {
            log::warn!("Inference requested but model is not loaded");
            return HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "Model not loaded on server. Check server logs for model load errors or set ALLOW_PLACEHOLDER=true to enable fallback responses for development."
            }));
        }
    }

    // Run inference through helper (centralizes LlamaParams and error handling)
    let result = match run_inference(
        state.get_ref(),
        &formatted_prompt,
        request.temperature,
        request.max_tokens,
    )
    .await
    {
        Ok(output) => output,
        Err(e) => {
            log::error!("Inference error: {}", e);
            return HttpResponse::InternalServerError()
                .json(serde_json::json!({"error": format!("Inference failed: {}", e)}));
        }
    };

    let elapsed = start_time.elapsed();
    log::info!("Inference completed in {:.2}s", elapsed.as_secs_f32());

    let prompt_tokens = estimate_tokens(&formatted_prompt);
    let completion_tokens = estimate_tokens(&result);
    let total_tokens = prompt_tokens + completion_tokens;

    let response = ChatResponse {
        id: format!("chatcmpl-{}", uuid::Uuid::new_v4()),
        object: "chat.completion".to_string(),
        created: chrono::Utc::now().timestamp() as u64,
        model: request.model.clone(),
        choices: vec![Choice {
            index: 0,
            message: Message {
                role: "assistant".to_string(),
                content: result,
            },
            finish_reason: "stop".to_string(),
        }],
        usage: Usage {
            prompt_tokens,
            completion_tokens,
            total_tokens,
        },
    };

    HttpResponse::Ok().json(response)
}

fn format_messages_for_llama(messages: &[Message]) -> String {
    let mut formatted = String::new();

    for message in messages {
        match message.role.as_str() {
            "system" => formatted.push_str(&format!("<|system|>\n{}\n", message.content)),
            "user" => formatted.push_str(&format!("<|user|>\n{}\n", message.content)),
            "assistant" => formatted.push_str(&format!("<|assistant|>\n{}\n", message.content)),
            _ => formatted.push_str(&format!("<|{}|>\n{}\n", message.role, message.content)),
        }
    }

    formatted.push_str("<|assistant|>\n");
    formatted
}

fn estimate_tokens(text: &str) -> u32 {
    // rough token estimate: 4 chars per token
    (text.len() / 4) as u32
}

// Centralized inference helper so LlamaParams are set in one place.
// Accept the application state so we can access the model and configuration.
async fn run_inference(
    app_state: &Arc<AppState>,
    prompt: &str,
    _temperature: f32, // currently unused (sampler doesn't expose temperature); keep param for API compatibility
    max_tokens: u32,
) -> Result<String> {
    // Lock the model for exclusive use during inference.
    let model_arc = app_state.model.clone();
    let guard = model_arc.lock().await;

    // If the model isn't loaded, return a placeholder when allowed, otherwise error.
    if guard.is_none() {
        if app_state.allow_placeholder {
            return Ok(format!("{}{}", prompt, "\n\n[generated placeholder]"));
        }
        return Err(anyhow!("Model not loaded on server"));
    }

    let model = guard.as_ref().unwrap();

    // Set parameters for this inference request
    let n_threads = std::thread::available_parallelism().map_or(2, |p| p.get());
    log::info!(
        "Configuring inference threads: {} (thread control is handled by the model or via parameters at load time)",
        n_threads
    );

    // Create session for this inference
    let mut session_params = llama_cpp::SessionParams::default();
    // session_params.n_threads expects a u32, but available_parallelism returns usize;
    // safely convert with a fallback to u32::MAX if the value doesn't fit.
    let n_threads_u32: u32 = n_threads.try_into().unwrap_or(u32::MAX);
    session_params.n_threads = n_threads_u32;

    // Create a session from the model
    let mut ctx = match model.create_session(session_params) {
        Ok(ctx) => ctx,
        Err(e) => return Err(anyhow!("Failed to create session: {}", e)),
    };

    // Feed the prompt into the context
    if let Err(e) = ctx.advance_context(prompt) {
        return Err(anyhow!("Failed to advance context: {}", e));
    }

    // Configure the sampler
    let sampler = llama_cpp::standard_sampler::StandardSampler::default();
    // Note: this version of the crate's StandardSampler does not expose a `temp` field.
    // If your crate version supports setting temperature, replace the line below with the appropriate setter.
    // For now we use the default sampler configuration.

    // Start token generation
    log::info!("Starting inference with max_tokens={}", max_tokens);

    // Generate completion using the sampler
    let completions = ctx.start_completing_with(sampler, max_tokens as usize)?;

    // Collect all generated tokens into a single string
    let mut output = String::new();
    for completion in completions {
        output.push_str(&format!("{:?}", completion));
    }

    log::info!("Completed inference. Output length: {} chars", output.len());

    Ok(output)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
    dotenv::dotenv().ok();

    let model_path = env::var("MODEL_PATH")
        .unwrap_or_else(|_| "/models/Phi-3-mini-4k-instruct-Q4_K_S.gguf".to_string());
    let port = env::var("PORT")
        .unwrap_or_else(|_| "3000".to_string())
        .parse::<u16>()
        .unwrap_or(3000);
    let n_parallel = env::var("N_PARALLEL")
        .unwrap_or_else(|_| "1".to_string())
        .parse::<usize>()
        .unwrap_or(1);

    // Try to load model (wrapped in an async Mutex so we can obtain mutable access for evaluation)
    let loaded_model = match LlamaModel::load_from_file(&model_path, LlamaParams::default()) {
        Ok(m) => {
            log::info!("Model loaded successfully from {}", model_path);
            Some(m)
        }
        Err(e) => {
            log::error!("Failed to load LLM model: {}", e);
            None
        }
    };

    // Create application state
    let model = Arc::new(Mutex::new(loaded_model));
    let allow_placeholder = env::var("ALLOW_PLACEHOLDER")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    let state = Arc::new(AppState {
        model: model.clone(),
        inference_semaphore: Semaphore::new(n_parallel * MAX_CONCURRENT_INFERENCES),
        allow_placeholder,
    });

    // Start HTTP server
    log::info!("Starting HTTP server on port {}", port);
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(state.clone()))
            .route("/", web::get().to(root))
            .route("/health", web::get().to(health))
            .route("/healthz", web::get().to(health))
            .route("/prompts", web::get().to(list_prompts))
            .route("/v1/chat/completions", web::post().to(generate))
    })
    .workers(num_cpus::get() * 2)
    .backlog(8192)
    .keep_alive(std::time::Duration::from_secs(75))
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
