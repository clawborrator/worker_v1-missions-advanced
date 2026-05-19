#!/usr/bin/env bash
# Spawn an ephemeral integrator container for Phase 3.5 wiring.
# Integrator writes the entry point (cmd/<app-name>/ for Go,
# src/main.ts for Node, etc) connecting the already-built modules.
#
# Usage:
#   bin/spawn-integrator.sh
#
# Required env:
#   MISSION_ID            correlation id
#   ORCH_ROUTING          orchestrator routing name
#   REPO_URL              target repo URL
#   REPO_PAT              PAT with push access
#   COMPLETED_MODULES     comma-joined list of module ids that
#                          completed Phase 3
#   ENTRY_POINT_PATH      repo-relative dir for the entry point
#                          (e.g. cmd/<app>/, src/main.ts)
#   ASSERTIONS            newline-joined integration-level assertions
#   UPSTREAM_ARTIFACTS    newline-joined paths the integrator must
#                          read first (always includes requirements,
#                          modules.json, interfaces.json, and every
#                          module's design.md)
#
# Optional:
#   INTEGRATOR_IMAGE      default ladder99/clawborrator-worker:latest
#
# Spawn-env vars are inherited from the orchestrator's environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/integrator-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${COMPLETED_MODULES:?COMPLETED_MODULES not set}"
: "${ENTRY_POINT_PATH:?ENTRY_POINT_PATH not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"
: "${UPSTREAM_ARTIFACTS:?UPSTREAM_ARTIFACTS not set}"

IMAGE="${INTEGRATOR_IMAGE:-ladder99/clawborrator-worker:latest}"

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
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{COMPLETED_MODULES}}"/$COMPLETED_MODULES}"
PROMPT="${PROMPT//"{{ENTRY_POINT_PATH}}"/$ENTRY_POINT_PATH}"
PROMPT="${PROMPT//"{{ASSERTIONS}}"/$ASSERTIONS}"
PROMPT="${PROMPT//"{{UPSTREAM_ARTIFACTS}}"/$UPSTREAM_ARTIFACTS}"

NAME="mission-integrator-${MISSION_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, entry=$ENTRY_POINT_PATH)"
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
