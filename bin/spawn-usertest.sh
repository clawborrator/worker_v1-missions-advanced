#!/usr/bin/env bash
# Spawn an ephemeral user-testing validator for one feature.
# Validator boots the app, exercises it via Playwright, calls
# submit_handoff, self-terminates. Uses the -playwright image variant
# (chromium + Xvfb included).
#
# Usage:
#   bin/spawn-usertest.sh <FEATURE_ID> <COMMIT_SHA>

set -euo pipefail

FEATURE_ID="${1:?usage: spawn-usertest.sh <feature-id> <commit-sha>}"
COMMIT_SHA="${2:?usage: spawn-usertest.sh <feature-id> <commit-sha>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/usertest-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"
: "${APP_START_CMD:?APP_START_CMD not set (e.g. 'npm run dev')}"
: "${APP_URL:?APP_URL not set (e.g. 'http://localhost:3000/')}"

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${USERTEST_IMAGE:-ladder99/clawborrator-worker-playwright:latest}"

PROMPT="$(python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{FEATURE_ID}}", os.environ["FEATURE_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{COMMIT_SHA}}", os.environ["COMMIT_SHA"])
  .replace("{{ASSERTIONS}}", os.environ["ASSERTIONS"])
  .replace("{{APP_START_CMD}}", os.environ["APP_START_CMD"])
  .replace("{{APP_URL}}", os.environ["APP_URL"]))
print(out, end="")
PYEOF
)"

NAME="mission-usertest-${FEATURE_ID}-$(date +%s)"

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
  -e APP_START_CMD="$APP_START_CMD" \
  -e APP_URL="$APP_URL" \
  -e CLAUDE_INITIAL_PROMPT="$PROMPT" \
  "$IMAGE"
