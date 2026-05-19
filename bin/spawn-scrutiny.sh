#!/usr/bin/env bash
# Spawn an ephemeral scrutiny validator for one feature.
# Validator runs tests + lint + code-review against the worker's commit,
# calls submit_handoff, self-terminates. No code mutation authority.
#
# Usage:
#   bin/spawn-scrutiny.sh <FEATURE_ID> <COMMIT_SHA>

set -euo pipefail

FEATURE_ID="${1:?usage: spawn-scrutiny.sh <feature-id> <commit-sha>}"
COMMIT_SHA="${2:?usage: spawn-scrutiny.sh <feature-id> <commit-sha>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/scrutiny-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${SCRUTINY_IMAGE:-ladder99/clawborrator-worker:latest}"

PROMPT="$(python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{FEATURE_ID}}", os.environ["FEATURE_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{COMMIT_SHA}}", os.environ["COMMIT_SHA"])
  .replace("{{ASSERTIONS}}", os.environ["ASSERTIONS"]))
print(out, end="")
PYEOF
)"

NAME="mission-scrutiny-${FEATURE_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, feature=$FEATURE_ID, commit=${COMMIT_SHA:0:8})"
FEATURE_ID="$FEATURE_ID" COMMIT_SHA="$COMMIT_SHA" \
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
