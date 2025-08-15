from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import os
import json
from typing import List, Optional
import httpx

app = FastAPI()

class Message(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    model: str
    messages: List[Message]
    temperature: Optional[float] = 0.7
    max_tokens: Optional[int] = 100

def read_prompt_file(prompt_name: str) -> str:
    prompt_path = f"/prompts/{prompt_name}.txt"
    if not os.path.exists(prompt_path):
        raise HTTPException(status_code=404, detail=f"Prompt template {prompt_name} not found")
    with open(prompt_path, 'r') as f:
        return f.read()

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

        async with httpx.AsyncClient() as client:
            resp = await client.post("http://localhost:8080/v1/chat/completions",
                                      json=payload,
                                      headers=headers,
                                      timeout=60.0)
            resp.raise_for_status()
            return resp.json()

    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Upstream request error: {str(e)}")
    except httpx.HTTPStatusError as e:
        raise HTTPException(status_code=500, detail=f"Upstream server error: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "3000")))
