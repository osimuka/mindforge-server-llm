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
    model: Arc<Mutex<LlamaModel>>,
    inference_semaphore: Semaphore,
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
    // Run inference through helper (centralizes LlamaParams and error handling)
    let result = match run_inference(
        &state.model,
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
// Accept the same model type stored in AppState (Arc<Mutex<LlamaModel>>).
async fn run_inference(
    model: &Arc<Mutex<LlamaModel>>,
    prompt: &str,
    _temperature: f32,
    _max_tokens: u32,
) -> Result<String> {
    // Lock the model for exclusive use during inference.
    // Depending on the llama_cpp API available to you, replace the placeholder
    // below with the actual generation/evaluation call.
    let _guard = model.lock().await;

    // Placeholder generation: return the prompt appended with a simple suffix.
    // Replace this with model.evaluate(...) or model.generate(...) if your binding supports it.
    Ok(format!("{}{}", prompt, "\n\n[generated placeholder]"))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));
    dotenv::dotenv().ok();

    let model_path = env::var("MODEL_PATH").unwrap_or_else(|_| "/models/model.gguf".to_string());
    let port = env::var("PORT")
        .unwrap_or_else(|_| "3000".to_string())
        .parse::<u16>()
        .unwrap_or(3000);
    let n_parallel = env::var("N_PARALLEL")
        .unwrap_or_else(|_| "1".to_string())
        .parse::<usize>()
        .unwrap_or(1);

    // Load model (wrapped in an async Mutex so we can obtain mutable access for evaluation)
    let model = Arc::new(Mutex::new(
        LlamaModel::load_from_file(&model_path, LlamaParams::default())
            .expect("Failed to load LLM model"),
    ));

    // Create application state
    let state = Arc::new(AppState {
        model: model.clone(),
        inference_semaphore: Semaphore::new(n_parallel * MAX_CONCURRENT_INFERENCES),
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
