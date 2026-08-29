#!/usr/bin/env bash

set -euo pipefail

: "${METACENTRUM_API_KEY:?METACENTRUM_API_KEY is not set}"

METACENTRUM_URL="https://llm.ai.e-infra.cz/v1/models"
CONFIG_FILE="config.yaml"

models=$(curl -fsSL \
  -H "Authorization: Bearer ${METACENTRUM_API_KEY}" \
  "${METACENTRUM_URL}" |
  jq -r '.data[].id')

cat > "${CONFIG_FILE}" <<EOF
model_list:
EOF

while IFS= read -r model; do
    cat >> "${CONFIG_FILE}" <<EOF
  - model_name: ${model}
    litellm_params:
      model: openai/${model}
      api_base: https://llm.ai.e-infra.cz/v1
      api_key: os.environ/METACENTRUM_API_KEY
EOF
done <<< "${models}"

cat >> "${CONFIG_FILE}" <<'EOF'

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  store_model_in_db: true
  store_prompts_in_spend_logs: true

litellm_settings:
  set_verbose: true
EOF

echo "Discovered models:"
echo "${models}"