#!/usr/bin/env bash
# Spawn an ephemeral module-builder container for one module of
# Phase 3 (parallel module implementation).
#
# Usage:
#   bin/spawn-module-builder.sh <MODULE_ID>
#
# Required env:
#   MISSION_ID            correlation id
#   ORCH_ROUTING          orchestrator routing name
#   REPO_URL              target repo URL
#   REPO_PAT              PAT with push access
#   MODULE_PURPOSE        from modules.json
#   MODULE_PATH           from modules.json (repo-relative dir)
#   MODULE_DEPS           comma-or-newline-joined list of dep module ids
#                          (empty string if no deps)
#   MODULE_SCAFFOLDS      comma-or-newline-joined list of scaffold ids
#                          (empty string if none used)
#   MODULE_PUBLIC_API     prose summary
#   ASSERTIONS            newline-joined assertion descriptions
#   UPSTREAM_ARTIFACTS    newline-joined list of in-repo paths the
#                          module-builder must read first (e.g.
#                          .mission/requirements.md\n.mission/interfaces.json)
#
# Optional:
#   MODULE_BUILDER_IMAGE  default ladder99/clawborrator-worker:latest
#
# Spawn-env vars are inherited from the orchestrator's environment.

set -euo pipefail

MODULE_ID="${1:?usage: spawn-module-builder.sh <module-id>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/module-builder-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${MODULE_PURPOSE:?MODULE_PURPOSE not set}"
: "${MODULE_PATH:?MODULE_PATH not set}"
: "${MODULE_PUBLIC_API:?MODULE_PUBLIC_API not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"
: "${UPSTREAM_ARTIFACTS:?UPSTREAM_ARTIFACTS not set}"
MODULE_DEPS="${MODULE_DEPS:-(none)}"
MODULE_SCAFFOLDS="${MODULE_SCAFFOLDS:-(none)}"

IMAGE="${MODULE_BUILDER_IMAGE:-ladder99/clawborrator-worker:latest}"

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
PROMPT="${PROMPT//"{{MODULE_ID}}"/$MODULE_ID}"
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{MODULE_PURPOSE}}"/$MODULE_PURPOSE}"
PROMPT="${PROMPT//"{{MODULE_PATH}}"/$MODULE_PATH}"
PROMPT="${PROMPT//"{{MODULE_DEPS}}"/$MODULE_DEPS}"
PROMPT="${PROMPT//"{{MODULE_SCAFFOLDS}}"/$MODULE_SCAFFOLDS}"
PROMPT="${PROMPT//"{{MODULE_PUBLIC_API}}"/$MODULE_PUBLIC_API}"
PROMPT="${PROMPT//"{{ASSERTIONS}}"/$ASSERTIONS}"
PROMPT="${PROMPT//"{{UPSTREAM_ARTIFACTS}}"/$UPSTREAM_ARTIFACTS}"

NAME="mission-module-${MODULE_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, module=$MODULE_ID, path=$MODULE_PATH)"
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
