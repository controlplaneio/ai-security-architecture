#!/usr/bin/env bats

if [ -z "$OPENAI_API_KEY" ]; then
  echo "Warning: OPENAI_API_KEY environment variable is not set."
  exit 1
fi

@test "Check that LLM responds Hello" {
  RESPONSE=$(curl -v -X POST -H "Content-Type: application/json" -d '{ "model": "proxy:gpt-4o", "messages": [{"role": "user", "content": "Say the word Hello once, with no punctuation"}], "temperature": 0.7 }' localhost:8080/v1/chat/completions)

  MESSAGE=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')

   [ "$MESSAGE" = "Hello" ]
}