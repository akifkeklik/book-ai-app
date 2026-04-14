from openai import OpenAI

client = OpenAI(
    api_key="OPENROUTER_API_KEY_BURAYA",
    base_url="https://openrouter.ai/api/v1"
)

response = client.chat.completions.create(
    model="anthropic/claude-3-haiku",
    messages=[
        {"role": "user", "content": "Merhaba, kendini tanıt"}
    ]
)

print(response.choices[0].message.content)