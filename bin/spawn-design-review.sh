#!/usr/bin/env bash
# Spawn an ephemeral design-review container for Phase 3.6.
# Boots the app, captures screenshots, compares against the design
# spec on color tokens, typography, spacing, component shape.
#
# Usage:
#   bin/spawn-design-review.sh
#
# Required env:
#   MISSION_ID            correlation id
#   ORCH_ROUTING          orchestrator routing name
#   REPO_URL              target repo URL
#   REPO_PAT              PAT with push access
#   DESIGN_SPEC_PATH      host-side absolute path to design spec md
#   APP_START_CMD         shell cmd to launch the app inside container
#   APP_URL               URL the design-review reaches the running app at
#   ASSERTIONS            newline-joined design-review assertions
#
# Optional:
#   DESIGN_REVIEW_IMAGE   default ladder99/clawborrator-worker-playwright:latest
#
# Spawn-env vars are inherited from the orchestrator's environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/design-review-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${DESIGN_SPEC_PATH:?DESIGN_SPEC_PATH not set}"
: "${APP_START_CMD:?APP_START_CMD not set}"
: "${APP_URL:?APP_URL not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"

if [[ ! -f "$DESIGN_SPEC_PATH" ]]; then
  echo "error: DESIGN_SPEC_PATH=$DESIGN_SPEC_PATH does not exist" >&2
  exit 2
fi

IMAGE="${DESIGN_REVIEW_IMAGE:-ladder99/clawborrator-worker-playwright:latest}"

: "${CLAUDE_CODE_OAUTH_TOKEN:?not set in orchestrator env}"
: "${CLAWBORRATOR_TOKEN:?not set in orchestrator env}"
: "${CLAWBORRATOR_HUB_URL:?not set in orchestrator env}"
: "${GIT_USER_EMAIL:?not set in orchestrator env}"
: "${GIT_USER_NAME:?not set in orchestrator env}"

DESIGN_SPEC_CONTAINER_PATH="/workspace/design-spec.md"

PROMPT=$(< "$TEMPLATE")
PROMPT="${PROMPT//"{{MISSION_ID}}"/$MISSION_ID}"
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{DESIGN_SPEC_PATH}}"/$DESIGN_SPEC_CONTAINER_PATH}"
PROMPT="${PROMPT//"{{APP_START_CMD}}"/$APP_START_CMD}"
PROMPT="${PROMPT//"{{APP_URL}}"/$APP_URL}"
PROMPT="${PROMPT//"{{ASSERTIONS}}"/$ASSERTIONS}"

NAME="mission-design-review-${MISSION_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, app-url=$APP_URL)"
exec docker run -dt --rm \
  --name "$NAME" \
  -e CLAUDE_CODE_OAUTH_TOKEN \
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
  -v "$DESIGN_SPEC_PATH:/workspace/design-spec.md:ro" \
  "$IMAGE"
