import logging
from typing import Optional
from ...domain.ports import LlmPort

logger = logging.getLogger(__name__)

class GenericLlmAdapter(LlmPort):
    def __init__(self, provider: str, api_key: str):
        self._provider = provider
        self._api_key = api_key

    def generate_response(self, system_prompt: str, user_prompt: str) -> Optional[str]:
        if not self._api_key:
            logger.error("LLM_API_KEY is missing.")
            return None
            
        try:
            if self._provider == "gemini":
                import google.generativeai as genai
                genai.configure(api_key=self._api_key)
                model = genai.GenerativeModel("gemini-1.5-flash")
                response = model.generate_content(
                    system_prompt + "\n\n" + user_prompt,
                    generation_config={"temperature": 0.3},
                    request_options={"timeout": 15.0} # Added timeout to prevent hanging
                )
                return response.text
                
            elif self._provider == "openai":
                from openai import OpenAI
                client = OpenAI(api_key=self._api_key, timeout=15.0) # Added timeout
                response = client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    temperature=0.3,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ]
                )
                return response.choices[0].message.content
            else:
                logger.error(f"Unsupported LLM provider: {self._provider}")
                return None
                
        except Exception as e:
            logger.error(f"LLM provider error: {e}")
            return None
