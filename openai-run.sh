# see https://platform.openai.com/docs/models
# see https://platform.openai.com/docs/guides/chat-completions


# if no arguments then print usage
if [ -z "$1" ]; then
  echo "Usage: openai-run.sh [model] <prompt>"
  exit 1
fi

if [ -z "$2" ]; then
  model="gpt-4o-mini"
  prompt="$1"
else
  model="$1"
  prompt="$2"
fi

curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$( jq -cn '{  "model": $ARGS.positional[0], "messages": [ { "role": "user", "content": $ARGS.positional[1] } ]  }' --args "$model" "$prompt" )"
