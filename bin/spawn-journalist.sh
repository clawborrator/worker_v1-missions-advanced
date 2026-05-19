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
#   CLAW_SPAWN_ENV        default ~/.clawborrator-spawn.env
#   JOURNALIST_IMAGE      default ladder99/clawborrator-worker:latest

set -euo pipefail

PHASE="${1:?usage: spawn-journalist.sh <phase>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/journalist-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${HANDOFFS_JSON_PATHS:?HANDOFFS_JSON_PATHS not set}"

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${JOURNALIST_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ ! -f "$SPAWN_ENV" ]]; then
  echo "error: $SPAWN_ENV not found" >&2
  exit 2
fi

ISO_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PROMPT="$(ISO8601_TS="$ISO_TS" PHASE="$PHASE" python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{PHASE}}", os.environ["PHASE"])
  .replace("{{HANDOFFS_JSON_PATHS}}", os.environ["HANDOFFS_JSON_PATHS"])
  .replace("{{ISO8601_TS}}", os.environ["ISO8601_TS"]))
print(out, end="")
PYEOF
)"

NAME="mission-journalist-${MISSION_ID}-${PHASE}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, phase=$PHASE)"
exec docker run -dt --rm \
  --name "$NAME" \
  --env-file "$SPAWN_ENV" \
  -e CLAWBORRATOR_EPHEMERAL=1 \
  -e CLAWBORRATOR_ROUTING_NAME="$NAME" \
  -e MODEL=haiku \
  -e CLAUDE_SKIP_PERMISSIONS=1 \
  -e REPO_URL="$REPO_URL" \
  -e REPO_PAT="$REPO_PAT" \
  -e CLAUDE_INITIAL_PROMPT="$PROMPT" \
  "$IMAGE"
