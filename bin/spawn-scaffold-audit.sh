#!/usr/bin/env bash
# Spawn an ephemeral scaffold-audit container for Phase 0 inventory.
# Audits /workspace/scaffold-libs (bind-mounted from host) and
# writes .mission/scaffold-inventory.json on a branch.
#
# Usage:
#   bin/spawn-scaffold-audit.sh
#
# Required env:
#   MISSION_ID            correlation id
#   ORCH_ROUTING          orchestrator routing name
#   REPO_URL              target repo URL
#   REPO_PAT              PAT with push access
#   SCAFFOLD_LIBS_PATH    host-side absolute path to scaffold libs folder
#
# Optional:
#   OPERATOR_NOTES        extra context from the operator (e.g. "ignore
#                         the libfoo-test directory, it's just a test rig")
#   CLAW_SPAWN_ENV        default ~/.clawborrator-spawn.env
#   SCAFFOLD_IMAGE        default ladder99/clawborrator-worker:latest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/scaffold-audit-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${SCAFFOLD_LIBS_PATH:?SCAFFOLD_LIBS_PATH not set}"
OPERATOR_NOTES="${OPERATOR_NOTES:-(none)}"

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${SCAFFOLD_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ ! -f "$SPAWN_ENV" ]]; then
  echo "error: $SPAWN_ENV not found" >&2
  exit 2
fi
if [[ ! -d "$SCAFFOLD_LIBS_PATH" ]]; then
  echo "error: SCAFFOLD_LIBS_PATH=$SCAFFOLD_LIBS_PATH does not exist" >&2
  exit 2
fi

PROMPT="$(python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{REPO_URL}}", os.environ["REPO_URL"])
  .replace("{{SCAFFOLD_LIBS_PATH}}", "/workspace/scaffold-libs")
  .replace("{{OPERATOR_NOTES}}", os.environ["OPERATOR_NOTES"]))
print(out, end="")
PYEOF
)"

NAME="mission-scaffold-audit-${MISSION_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, scaffold-libs=$SCAFFOLD_LIBS_PATH)"
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
  -v "$SCAFFOLD_LIBS_PATH:/workspace/scaffold-libs:ro" \
  "$IMAGE"
