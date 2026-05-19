#!/usr/bin/env bash
# Spawn an ephemeral architect container for Phase 0 ingestion.
# Architect reads the target repo's planning-docs/ folder (inside
# the cloned REPO_URL), produces .mission/requirements.md + draft
# modules.json + draft interfaces.json, commits + pushes on its
# own branch, submits handoff, self-terminates.
#
# Usage:
#   bin/spawn-architect.sh
#
# Required env (from your orchestrator):
#   MISSION_ID            correlation id
#   ORCH_ROUTING          your routing name (without leading @)
#   REPO_URL              target repo URL (must contain planning-docs/)
#   REPO_PAT              PAT with push access
#   GOAL_SUMMARY          one-paragraph operator goal description
#
# Optional:
#   PLANNING_DOCS_SUBPATH default "planning-docs" — repo-relative path
#                           the architect should read planning prose from
#   REVISION_NOTES        if respawning after operator revisions
#   ARCHITECT_IMAGE       default ladder99/clawborrator-worker:latest
#
# Spawn-env: this script does NOT read ~/.clawborrator-spawn.env. The
# orchestrator inherits the spawn-env at its own startup via
# --env-file, and this script passes the relevant vars through with
# `docker run -e VAR` (no value). That sidesteps the host's mode-600
# file being unreadable from inside the orchestrator container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/architect-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${GOAL_SUMMARY:?GOAL_SUMMARY not set}"
PLANNING_DOCS_SUBPATH="${PLANNING_DOCS_SUBPATH:-planning-docs}"
REVISION_NOTES="${REVISION_NOTES:-(no revisions)}"

IMAGE="${ARCHITECT_IMAGE:-ladder99/clawborrator-worker:latest}"

# Spawn-env keys we pass through to the spawned worker. These must
# already be present in this script's environment (the orchestrator
# inherited them from its own --env-file at startup). We use docker's
# `-e VAR` pass-through (no value) instead of `--env-file <path>`
# so we don't need the host's mode-600 spawn-env file to be readable
# from inside the orchestrator container.
# Anthropic auth: at least one of three must be set. Worker image
# picks whichever is present (preferred order: OAUTH > API_KEY >
# ACCESS_TOKEN). API_KEY disables clawborrator channels though,
# which breaks submit_handoff — the orchestrator's playbook check
# warns on that case.
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -z "${ANTHROPIC_API_KEY:-}" && -z "${ANTHROPIC_ACCESS_TOKEN:-}" ]]; then
  echo "error: no Anthropic auth in env (need one of CLAUDE_CODE_OAUTH_TOKEN, ANTHROPIC_API_KEY, ANTHROPIC_ACCESS_TOKEN)" >&2
  exit 2
fi

: "${CLAWBORRATOR_TOKEN:?not set in orchestrator env}"
: "${CLAWBORRATOR_HUB_URL:?not set in orchestrator env}"
: "${GIT_USER_EMAIL:?not set in orchestrator env}"
: "${GIT_USER_NAME:?not set in orchestrator env}"

PLANNING_DOCS_PATH="/workspace/repo/$PLANNING_DOCS_SUBPATH"

PROMPT=$(< "$TEMPLATE")
PROMPT="${PROMPT//"{{MISSION_ID}}"/$MISSION_ID}"
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{REPO_URL}}"/$REPO_URL}"
PROMPT="${PROMPT//"{{PLANNING_DOCS_PATH}}"/$PLANNING_DOCS_PATH}"
PROMPT="${PROMPT//"{{GOAL_SUMMARY}}"/$GOAL_SUMMARY}"
PROMPT="${PROMPT//"{{REVISION_NOTES}}"/$REVISION_NOTES}"

NAME="mission-architect-${MISSION_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, planning-docs=/workspace/repo/$PLANNING_DOCS_SUBPATH inside target repo)"
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
