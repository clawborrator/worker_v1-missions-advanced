#!/usr/bin/env bash
# Spawn an ephemeral scaffold-audit container for Phase 0 inventory.
# Audits the target repo's scaffold-libs/ folder (inside the cloned
# REPO_URL) and writes .mission/scaffold-inventory.json on a branch.
#
# Usage:
#   bin/spawn-scaffold-audit.sh
#
# Required env:
#   MISSION_ID            correlation id
#   ORCH_ROUTING          orchestrator routing name
#   REPO_URL              target repo URL (must contain scaffold-libs/)
#   REPO_PAT              PAT with push access
#
# Optional:
#   SCAFFOLD_LIBS_SUBPATH default "scaffold-libs" — repo-relative path
#                           to the scaffold libraries directory
#   OPERATOR_NOTES        extra context from the operator (e.g. "ignore
#                         the libfoo-test directory, it's just a test rig")
#   SCAFFOLD_IMAGE        default ladder99/clawborrator-worker:latest
#
# Spawn-env vars are passed through via `docker run -e VAR` from the
# orchestrator's own environment (loaded at its startup via --env-file).
# No host-side file access required.

set -euo pipefail

# Re-source spawn-env (see spawn-architect.sh for full explanation).
if [[ -r /spawn.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /spawn.env
  set +a
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/scaffold-audit-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
SCAFFOLD_LIBS_SUBPATH="${SCAFFOLD_LIBS_SUBPATH:-scaffold-libs}"
OPERATOR_NOTES="${OPERATOR_NOTES:-(none)}"

IMAGE="${SCAFFOLD_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" && -z "${ANTHROPIC_ACCESS_TOKEN:-}" ]]; then
  echo "error: no Anthropic auth in env (need one of CLAUDE_CODE_OAUTH_TOKEN, ANTHROPIC_API_KEY, ANTHROPIC_ACCESS_TOKEN)" >&2
  exit 2
fi
: "${CLAWBORRATOR_TOKEN:?not set in orchestrator env}"
: "${CLAWBORRATOR_HUB_URL:?not set in orchestrator env}"
: "${GIT_USER_EMAIL:?not set in orchestrator env}"
: "${GIT_USER_NAME:?not set in orchestrator env}"

SCAFFOLD_LIBS_PATH="/workspace/repo/$SCAFFOLD_LIBS_SUBPATH"

PROMPT=$(< "$TEMPLATE")
PROMPT="${PROMPT//"{{MISSION_ID}}"/$MISSION_ID}"
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{REPO_URL}}"/$REPO_URL}"
PROMPT="${PROMPT//"{{SCAFFOLD_LIBS_PATH}}"/$SCAFFOLD_LIBS_PATH}"
PROMPT="${PROMPT//"{{OPERATOR_NOTES}}"/$OPERATOR_NOTES}"

NAME="mission-scaffold-audit-${MISSION_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, scaffold-libs=/workspace/repo/$SCAFFOLD_LIBS_SUBPATH inside target repo)"
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
  -e MODEL="${MODEL:-opus}" \
  -e CLAUDE_SKIP_PERMISSIONS=1 \
  -e REPO_URL="$REPO_URL" \
  -e REPO_PAT="$REPO_PAT" \
  -e CLAUDE_INITIAL_PROMPT="$PROMPT" \
  "$IMAGE"
