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
#   CLAW_SPAWN_ENV        default ~/.clawborrator-spawn.env (host path)
#   ARCHITECT_IMAGE       default ladder99/clawborrator-worker:latest

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

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${ARCHITECT_IMAGE:-ladder99/clawborrator-worker:latest}"

# Note: SPAWN_ENV is a HOST path (docker daemon resolves bind paths
# from host fs). When run inside an orchestrator container, a local
# [[ -f ]] check would always fail — skip it. docker run errors
# clearly if the path is wrong.

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
  --env-file "$SPAWN_ENV" \
  -e CLAWBORRATOR_EPHEMERAL=1 \
  -e CLAWBORRATOR_ROUTING_NAME="$NAME" \
  -e MODEL=sonnet \
  -e CLAUDE_SKIP_PERMISSIONS=1 \
  -e REPO_URL="$REPO_URL" \
  -e REPO_PAT="$REPO_PAT" \
  -e CLAUDE_INITIAL_PROMPT="$PROMPT" \
  "$IMAGE"
