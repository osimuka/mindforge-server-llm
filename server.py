import os
import json
import time
import httpx

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import List, Optional
from functools import lru_cache
from prometheus_fastapi_instrumentator import Instrumentator


# Create a global client for connection pooling
http_client = httpx.AsyncClient(timeout=60.0)
app = FastAPI()

# Instrument metrics at import time so middleware is registered before Uvicorn
Instrumentator().instrument(app).expose(app)

# Add shutdown event to close client
@app.on_event("shutdown")
async def shutdown_event():
    await http_client.aclose()


class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    model: str
    messages: List[Message]
    temperature: Optional[float] = 0.7
    max_tokens: Optional[int] = 100

    class Config:
        # Optimize validation
        validate_assignment = True
        extra = "forbid"

@lru_cache(maxsize=32)
def read_prompt_file(prompt_name: str) -> str:
    prompt_path = f"/prompts/{prompt_name}.txt"
    if not os.path.exists(prompt_path):
        raise HTTPException(status_code=404, detail=f"Prompt template {prompt_name} not found")
    with open(prompt_path, 'r') as f:
        return f.read()


@app.get("/")
async def root():
    return {"status": "ok"}

@app.get("/healthz")
async def healthz():
    # Cache health check results for 5 seconds
    current_time = time.time()
    last_check = getattr(healthz, "last_check_time", 0)
    last_status = getattr(healthz, "last_status", None)

    # Only check upstream every 5 seconds
    if current_time - last_check > 5 or last_status is None:
        try:
            # Use global client instead of creating a new one
            r = await http_client.get("http://127.0.0.1:8080/", timeout=2.0)
            if r.status_code < 500:
                healthz.last_status = {"status": "ok", "upstream": True}
            else:
                healthz.last_status = {"status": "degraded", "upstream": False}
        except Exception:
            healthz.last_status = {"status": "degraded", "upstream": False}
            healthz.last_check_time = current_time

    return healthz.last_status

@app.post("/v1/chat/completions")
async def generate(request: ChatRequest, prompt: Optional[str] = None):
    try:
        system_prompt = ""
        if prompt:
            system_prompt = read_prompt_file(prompt)

        # Prepare messages including system prompt if provided
        messages = [ {"role": m.role, "content": m.content} for m in request.messages ]
        if system_prompt:
            messages.insert(0, {"role":"system", "content": system_prompt})

        payload = {
            "model": request.model,
            "messages": messages,
            "temperature": request.temperature,
            "max_tokens": request.max_tokens
        }

        headers = {"Content-Type": "application/json"}

        # Use global client instead of creating a new one each time
        resp = await http_client.post("http://localhost:8080/v1/chat/completions",
                                    json=payload,
                                    headers=headers)
        resp.raise_for_status()
        return resp.json()

    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Upstream request error: {str(e)}")
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=500, detail=f"Upstream server error: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/chat/completions/stream")
async def generate_stream(request: ChatRequest, prompt: Optional[str] = None):
    async def response_generator():
        try:
            system_prompt = ""
            if prompt:
                system_prompt = read_prompt_file(prompt)

            messages = [{"role": m.role, "content": m.content} for m in request.messages]
            if system_prompt:
                messages.insert(0, {"role": "system", "content": system_prompt})

            payload = {
                "model": request.model,
                "messages": messages,
                "temperature": request.temperature,
                "max_tokens": request.max_tokens,
                "stream": True
            }

            headers = {"Content-Type": "application/json"}

            async with http_client.stream(
                "POST",
                "http://localhost:8080/v1/chat/completions",
                json=payload,
                headers=headers,
                timeout=120.0
            ) as response:
                async for chunk in response.aiter_bytes():
                    yield chunk

        except Exception as e:
            yield json.dumps({"error": str(e)}).encode()

    return StreamingResponse(response_generator(), media_type="application/json")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "3000")))
