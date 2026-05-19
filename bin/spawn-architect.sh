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

if [[ ! -f "$SPAWN_ENV" ]]; then
  echo "error: $SPAWN_ENV not found" >&2
  exit 2
fi

PROMPT="$(PLANNING_DOCS_SUBPATH="$PLANNING_DOCS_SUBPATH" python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{REPO_URL}}", os.environ["REPO_URL"])
  .replace("{{PLANNING_DOCS_PATH}}", "/workspace/repo/" + os.environ["PLANNING_DOCS_SUBPATH"])
  .replace("{{GOAL_SUMMARY}}", os.environ["GOAL_SUMMARY"])
  .replace("{{REVISION_NOTES}}", os.environ["REVISION_NOTES"]))
print(out, end="")
PYEOF
)"

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
