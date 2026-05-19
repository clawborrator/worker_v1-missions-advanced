#!/usr/bin/env bash
# Spawn a hardware-test container for Phase 3.7.
# Project-specific: requires a custom image that has the hardware-
# side tooling preinstalled. The default worker image does NOT
# include hardware drivers / SDKs.
#
# Operator approval REQUIRED before the orchestrator invokes this.
#
# Usage:
#   bin/spawn-hardware-test.sh
#
# Required env:
#   MISSION_ID              correlation id
#   ORCH_ROUTING            orchestrator routing name
#   REPO_URL                target repo URL
#   REPO_PAT                PAT with push access
#   INTEGRATED_COMMIT       SHA of the integration commit to test
#   APP_START_CMD           shell cmd to launch the integrated binary
#   HARDWARE_CONFIG_PATH    host-side absolute path to the project-
#                            specific config file the binary needs
#                            to talk to the real system (device
#                            addresses, endpoint URLs, credentials)
#   ASSERTIONS              newline-joined hardware-test assertions
#   HARDWARE_TEST_IMAGE     REQUIRED. project-specific image with
#                            the right hardware tooling.
#
# Optional:
#   CLAW_SPAWN_ENV          default ~/.clawborrator-spawn.env
#   NETWORK_MODE            docker network mode (default `host` so
#                            the binary can reach hardware on the LAN)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/hardware-test-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${INTEGRATED_COMMIT:?INTEGRATED_COMMIT not set}"
: "${APP_START_CMD:?APP_START_CMD not set}"
: "${HARDWARE_CONFIG_PATH:?HARDWARE_CONFIG_PATH not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"
: "${HARDWARE_TEST_IMAGE:?HARDWARE_TEST_IMAGE not set — provide a project-specific image}"

if [[ ! -f "$HARDWARE_CONFIG_PATH" ]]; then
  echo "error: HARDWARE_CONFIG_PATH=$HARDWARE_CONFIG_PATH does not exist" >&2
  exit 2
fi

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
NETWORK_MODE="${NETWORK_MODE:-host}"

if [[ ! -f "$SPAWN_ENV" ]]; then
  echo "error: $SPAWN_ENV not found" >&2
  exit 2
fi

PROMPT="$(python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{INTEGRATED_COMMIT}}", os.environ["INTEGRATED_COMMIT"])
  .replace("{{APP_START_CMD}}", os.environ["APP_START_CMD"])
  .replace("{{HARDWARE_CONFIG_PATH}}", "/workspace/hardware-config")
  .replace("{{ASSERTIONS}}", os.environ["ASSERTIONS"]))
print(out, end="")
PYEOF
)"

NAME="mission-hardware-test-${MISSION_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, commit=$INTEGRATED_COMMIT, image=$HARDWARE_TEST_IMAGE)"
echo "WARNING: this container will interact with real hardware. Operator approval is presumed."
exec docker run -dt --rm \
  --name "$NAME" \
  --network "$NETWORK_MODE" \
  --env-file "$SPAWN_ENV" \
  -e CLAWBORRATOR_EPHEMERAL=1 \
  -e CLAWBORRATOR_ROUTING_NAME="$NAME" \
  -e MODEL=sonnet \
  -e CLAUDE_SKIP_PERMISSIONS=1 \
  -e REPO_URL="$REPO_URL" \
  -e REPO_PAT="$REPO_PAT" \
  -e INTEGRATED_COMMIT="$INTEGRATED_COMMIT" \
  -e CLAUDE_INITIAL_PROMPT="$PROMPT" \
  -v "$HARDWARE_CONFIG_PATH:/workspace/hardware-config:ro" \
  "$HARDWARE_TEST_IMAGE"
