#!/usr/bin/env bash
# Spawn an ephemeral scrutiny validator for one feature.
# Validator runs tests + lint + code-review against the worker's commit,
# calls submit_handoff, self-terminates. No code mutation authority.
#
# Usage:
#   bin/spawn-scrutiny.sh <FEATURE_ID> <COMMIT_SHA>

set -euo pipefail

FEATURE_ID="${1:?usage: spawn-scrutiny.sh <feature-id> <commit-sha>}"
COMMIT_SHA="${2:?usage: spawn-scrutiny.sh <feature-id> <commit-sha>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/scrutiny-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"

IMAGE="${SCRUTINY_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" && -z "${ANTHROPIC_ACCESS_TOKEN:-}" ]]; then
  echo "error: no Anthropic auth in env (need one of CLAUDE_CODE_OAUTH_TOKEN, ANTHROPIC_API_KEY, ANTHROPIC_ACCESS_TOKEN)" >&2
  exit 2
fi
: "${CLAWBORRATOR_TOKEN:?not set in orchestrator env}"
: "${CLAWBORRATOR_HUB_URL:?not set in orchestrator env}"
: "${GIT_USER_EMAIL:?not set in orchestrator env}"
: "${GIT_USER_NAME:?not set in orchestrator env}"

PROMPT=$(< "$TEMPLATE")
PROMPT="${PROMPT//"{{MISSION_ID}}"/$MISSION_ID}"
PROMPT="${PROMPT//"{{FEATURE_ID}}"/$FEATURE_ID}"
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{COMMIT_SHA}}"/$COMMIT_SHA}"
PROMPT="${PROMPT//"{{ASSERTIONS}}"/$ASSERTIONS}"

NAME="mission-scrutiny-${FEATURE_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, feature=$FEATURE_ID, commit=${COMMIT_SHA:0:8})"
FEATURE_ID="$FEATURE_ID" COMMIT_SHA="$COMMIT_SHA" \
exec docker run -dt --rm \
  --name "$NAME" \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e ANTHROPIC_API_KEY \
  -e ANTHROPIC_ACCESS_TOKEN \
  -e CLAWBORRATOR_TOKEN \
  -e CLAWBORRATOR_HUB_URL \
  -e GIT_USER_EMAIL \
  -e GIT_USER_NAME \
  -e CLAWBORRATOR_EPHEMERAL=1 \
  -e CLAWBORRATOR_ROUTING_NAME="$NAME" \
  -e MODEL=sonnet \
  -e CLAUDE_SKIP_PERMISSIONS=1 \
  -e REPO_URL="$REPO_URL" \
  -e REPO_PAT="$REPO_PAT" \
  -e CLAUDE_INITIAL_PROMPT="$PROMPT" \
  "$IMAGE"
