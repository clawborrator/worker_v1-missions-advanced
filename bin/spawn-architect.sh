#!/usr/bin/env bash
# Spawn an ephemeral architect container for Phase 0 ingestion.
# Architect reads /workspace/planning-docs (bind-mounted from host),
# produces .mission/requirements.md + draft modules.json + draft
# interfaces.json in the target repo, commits + pushes on its own
# branch, submits handoff, self-terminates.
#
# Usage:
#   bin/spawn-architect.sh
#
# Required env (from your orchestrator):
#   MISSION_ID            correlation id
#   ORCH_ROUTING          your routing name (without leading @)
#   REPO_URL              target repo URL
#   REPO_PAT              PAT with push access
#   PLANNING_DOCS_PATH    host-side absolute path to planning-docs folder
#   GOAL_SUMMARY          one-paragraph operator goal description
#
# Optional:
#   REVISION_NOTES        if respawning after operator revisions
#   CLAW_SPAWN_ENV        default ~/.clawborrator-spawn.env
#   ARCHITECT_IMAGE       default ladder99/clawborrator-worker:latest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/architect-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${PLANNING_DOCS_PATH:?PLANNING_DOCS_PATH not set}"
: "${GOAL_SUMMARY:?GOAL_SUMMARY not set}"
REVISION_NOTES="${REVISION_NOTES:-(no revisions)}"

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${ARCHITECT_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ ! -f "$SPAWN_ENV" ]]; then
  echo "error: $SPAWN_ENV not found" >&2
  exit 2
fi

if [[ ! -d "$PLANNING_DOCS_PATH" ]]; then
  echo "error: PLANNING_DOCS_PATH=$PLANNING_DOCS_PATH does not exist" >&2
  exit 2
fi

PROMPT="$(python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{REPO_URL}}", os.environ["REPO_URL"])
  .replace("{{PLANNING_DOCS_PATH}}", "/workspace/planning-docs")
  .replace("{{GOAL_SUMMARY}}", os.environ["GOAL_SUMMARY"])
  .replace("{{REVISION_NOTES}}", os.environ["REVISION_NOTES"]))
print(out, end="")
PYEOF
)"

NAME="mission-architect-${MISSION_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, planning-docs=$PLANNING_DOCS_PATH)"
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
  -v "$PLANNING_DOCS_PATH:/workspace/planning-docs:ro" \
  "$IMAGE"
