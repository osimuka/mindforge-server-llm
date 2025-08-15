from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import os
import subprocess
import json
from typing import List, Optional

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
        messages = request.messages
        if system_prompt:
            messages.insert(0, Message(role="system", content=system_prompt))

        # Prepare the curl command to llama server
        cmd = [
            "curl", 
            "http://localhost:8080/v1/chat/completions",
            "-H", "Content-Type: application/json",
            "-d", json.dumps({
                "model": request.model,
                "messages": [{"role": m.role, "content": m.content} for m in messages],
                "temperature": request.temperature,
                "max_tokens": request.max_tokens
            })
        ]
        
        # Execute the command
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            raise HTTPException(status_code=500, detail=f"Llama server error: {result.stderr}")
            
        return json.loads(result.stdout)
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "3000")))
