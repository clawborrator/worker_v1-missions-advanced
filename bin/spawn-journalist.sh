#!/usr/bin/env bash
# Spawn an ephemeral journalist container at the end of a phase.
# Reads recent handoffs + state.json, appends a narrative summary
# to .mission/journal.md on main.
#
# Usage:
#   bin/spawn-journalist.sh <PHASE>
#
# Required env:
#   MISSION_ID            correlation id
#   ORCH_ROUTING          orchestrator routing name
#   REPO_URL              target repo URL
#   REPO_PAT              PAT with push access
#   HANDOFFS_JSON_PATHS   newline-joined repo-relative paths to the
#                          handoff JSON files this phase produced
#                          (under .mission/artifacts/)
#
# Optional:
#   JOURNALIST_IMAGE      default ladder99/clawborrator-worker:latest
#
# Spawn-env vars are inherited from the orchestrator's environment.

set -euo pipefail

PHASE="${1:?usage: spawn-journalist.sh <phase>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/journalist-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${HANDOFFS_JSON_PATHS:?HANDOFFS_JSON_PATHS not set}"

IMAGE="${JOURNALIST_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" && -z "${ANTHROPIC_ACCESS_TOKEN:-}" ]]; then
  echo "error: no Anthropic auth in env (need one of CLAUDE_CODE_OAUTH_TOKEN, ANTHROPIC_API_KEY, ANTHROPIC_ACCESS_TOKEN)" >&2
  exit 2
fi
: "${CLAWBORRATOR_TOKEN:?not set in orchestrator env}"
: "${CLAWBORRATOR_HUB_URL:?not set in orchestrator env}"
: "${GIT_USER_EMAIL:?not set in orchestrator env}"
: "${GIT_USER_NAME:?not set in orchestrator env}"

ISO_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PROMPT=$(< "$TEMPLATE")
PROMPT="${PROMPT//"{{MISSION_ID}}"/$MISSION_ID}"
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{PHASE}}"/$PHASE}"
PROMPT="${PROMPT//"{{HANDOFFS_JSON_PATHS}}"/$HANDOFFS_JSON_PATHS}"
PROMPT="${PROMPT//"{{ISO8601_TS}}"/$ISO_TS}"

NAME="mission-journalist-${MISSION_ID}-${PHASE}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, phase=$PHASE)"
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
  -e MODEL=haiku \
  -e CLAUDE_SKIP_PERMISSIONS=1 \
  -e REPO_URL="$REPO_URL" \
  -e REPO_PAT="$REPO_PAT" \
  -e CLAUDE_INITIAL_PROMPT="$PROMPT" \
  "$IMAGE"
