#!/usr/bin/env bash
# Spawn an ephemeral mission-worker container for one feature.
# Worker implements the feature, commits + pushes, calls submit_handoff,
# self-terminates. Orchestrator (this script's caller) parses the
# handoff JSON from the resulting <channel> turn and decides next step.
#
# Usage:
#   bin/spawn-worker.sh <FEATURE_ID>
#
# Required env (load from your orchestrator's own env):
#   MISSION_ID         correlation id for this mission
#   ORCH_ROUTING       your routing-name (e.g. @missions-orchestrator-pwreset)
#   REPO_URL           target repo the worker will clone + modify
#   REPO_PAT           PAT with push access to REPO_URL
#   FEATURE_SPEC       prose description of the feature (passed via stdin
#                       or sourced from .mission/features.json by caller)
#   ASSERTIONS         newline-joined string of assertions for this feature
#
# Optional:
#   CLAW_SPAWN_ENV     default ~/.clawborrator-spawn.env
#   PROBE_IMAGE        default ladder99/clawborrator-worker:latest

set -euo pipefail

FEATURE_ID="${1:?usage: spawn-worker.sh <feature-id>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/worker-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${FEATURE_SPEC:?FEATURE_SPEC not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${PROBE_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ ! -f "$SPAWN_ENV" ]]; then
  echo "error: $SPAWN_ENV not found; see README.md" >&2
  exit 2
fi

# Render the prompt template. Use a Python heredoc to avoid sed
# escaping pain with multi-line FEATURE_SPEC / ASSERTIONS values.
PROMPT="$(python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{FEATURE_ID}}", os.environ["FEATURE_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{FEATURE_SPEC}}", os.environ["FEATURE_SPEC"])
  .replace("{{ASSERTIONS}}", os.environ["ASSERTIONS"]))
print(out, end="")
PYEOF
)"

NAME="mission-worker-${FEATURE_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, feature=$FEATURE_ID)"
FEATURE_ID="$FEATURE_ID" \
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
