#!/bin/bash
# scripts/import_workflows.sh - Import automatico workflow n8n

set -euo pipefail

# Script Configuration
readonly N8N_BASE_URL="http://localhost:5678" # Assuming n8n runs on localhost:5678
readonly WORKFLOW_FILE_PATH="workflows/n8n_mcp_workflows.json" # Path relative to project root
readonly MAX_WAIT_SECONDS=60 # Max time to wait for n8n to be ready
readonly RETRY_DELAY_SECONDS=5

# Color codes for output (optional, but nice for logs)
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install jq to proceed."
    exit 1
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    log_error "curl is not installed. Please install curl to proceed."
    exit 1
fi


log_info "Starting n8n workflow import process..."

# Wait for n8n to be ready
log_info "Waiting for n8n to be ready at $N8N_BASE_URL (max ${MAX_WAIT_SECONDS}s)..."
elapsed_time=0
while [[ $elapsed_time -lt $MAX_WAIT_SECONDS ]]; do
   if curl -s -f "$N8N_BASE_URL/healthz" > /dev/null 2>&1; then
      log_info "n8n is ready!"
      break
   fi
   sleep $RETRY_DELAY_SECONDS
   elapsed_time=$((elapsed_time + RETRY_DELAY_SECONDS))
   echo -n "." # Progress indicator
done

if [[ $elapsed_time -ge $MAX_WAIT_SECONDS ]]; then
   log_error "n8n did not become ready within $MAX_WAIT_SECONDS seconds. Aborting workflow import."
   exit 1
fi
echo # Newline after progress dots

# Check if workflow file exists
if [[ ! -f "$WORKFLOW_FILE_PATH" ]]; then
    log_error "Workflow file not found at $WORKFLOW_FILE_PATH"
    exit 1
fi

# Read the main JSON file containing the list of workflows
ALL_WORKFLOWS_JSON=$(cat "$WORKFLOW_FILE_PATH")

# Count number of workflows
NUM_WORKFLOWS=$(echo "$ALL_WORKFLOWS_JSON" | jq '.workflows | length')
log_info "Found $NUM_WORKFLOWS workflow(s) in $WORKFLOW_FILE_PATH."

# Import each workflow
# Note: n8n API for importing workflows usually expects a single workflow object, not an array under "workflows".
# The structure in `n8n_mcp_workflows.json` is `{"workflows": [...]}`.
# We need to iterate through this array and import each object.

echo "$ALL_WORKFLOWS_JSON" | jq -c '.workflows[]' | while IFS= read -r workflow_json_str; do
   workflow_name=$(echo "$workflow_json_str" | jq -r '.name // "Unnamed Workflow"')
   log_info "Attempting to import workflow: '$workflow_name'..."

   # n8n's POST /rest/workflows expects the workflow object directly.
   import_response=$(curl -s -X POST "$N8N_BASE_URL/rest/workflows" \
     -H "Content-Type: application/json" \
     -d "$workflow_json_str")

   # Check response for success (n8n usually returns the imported workflow with an ID)
   imported_id=$(echo "$import_response" | jq -r '.id // empty')

   if [[ -n "$imported_id" ]]; then
      log_info "Successfully imported workflow '$workflow_name' with ID: $imported_id"

      # Attempt to activate the workflow
      # n8n's PATCH /rest/workflows/{id} can be used to update, including activation.
      # However, the API might have changed. A common way is to use the /activate endpoint if available,
      # or simply ensure 'active: true' is in the JSON. The provided JSON already has "active": true.
      # For robustness, let's try to ensure it's active.
      # The workflow JSON itself should have "active": true. If the import respects that, this step might be redundant.
      # If a specific activation endpoint is needed:
      # activate_response=$(curl -s -X POST "$N8N_BASE_URL/rest/workflows/$imported_id/activate")
      # activate_success=$(echo "$activate_response" | jq -r '.active // false')
      # if [[ "$activate_success" == "true" ]]; then
      #    log_info "Workflow '$workflow_name' (ID: $imported_id) activated."
      # else
      #    log_warn "Could not activate workflow '$workflow_name' (ID: $imported_id) via API. Response: $activate_response. Please check n8n UI."
      # fi
      # Since "active: true" is in the workflow JSON, direct activation call might not be needed if import honors it.
      # We can verify if it's active.
      verification_response=$(curl -s "$N8N_BASE_URL/rest/workflows/$imported_id")
      is_active=$(echo "$verification_response" | jq -r '.active // false')
      if [[ "$is_active" == "true" ]]; then
          log_info "Verified workflow '$workflow_name' (ID: $imported_id) is active."
      else
          log_warn "Workflow '$workflow_name' (ID: $imported_id) was imported but is not active. Please activate it manually in the n8n UI."
      fi

   else
      log_error "Failed to import workflow '$workflow_name'."
      log_error "n8n Response: $import_response"
      # Consider exiting on first error or continuing. For now, continue.
   fi
   echo # Spacer
done

log_info "Workflow import process completed."
log_warn "Please verify in the n8n UI (http://localhost:5678) that all workflows are imported and active as expected."
