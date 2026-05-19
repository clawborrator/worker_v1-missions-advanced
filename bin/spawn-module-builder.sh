#!/usr/bin/env bash
# Spawn an ephemeral module-builder container for one module of
# Phase 3 (parallel module implementation).
#
# Usage:
#   bin/spawn-module-builder.sh <MODULE_ID>
#
# Required env:
#   MISSION_ID            correlation id
#   ORCH_ROUTING          orchestrator routing name
#   REPO_URL              target repo URL
#   REPO_PAT              PAT with push access
#   MODULE_PURPOSE        from modules.json
#   MODULE_PATH           from modules.json (repo-relative dir)
#   MODULE_DEPS           comma-or-newline-joined list of dep module ids
#                          (empty string if no deps)
#   MODULE_SCAFFOLDS      comma-or-newline-joined list of scaffold ids
#                          (empty string if none used)
#   MODULE_PUBLIC_API     prose summary
#   ASSERTIONS            newline-joined assertion descriptions
#   UPSTREAM_ARTIFACTS    newline-joined list of in-repo paths the
#                          module-builder must read first (e.g.
#                          .mission/requirements.md\n.mission/interfaces.json)
#
# Optional:
#   CLAW_SPAWN_ENV        default ~/.clawborrator-spawn.env
#   MODULE_BUILDER_IMAGE  default ladder99/clawborrator-worker:latest

set -euo pipefail

MODULE_ID="${1:?usage: spawn-module-builder.sh <module-id>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/module-builder-prompt.tmpl"

: "${MISSION_ID:?MISSION_ID not set}"
: "${ORCH_ROUTING:?ORCH_ROUTING not set}"
: "${REPO_URL:?REPO_URL not set}"
: "${REPO_PAT:?REPO_PAT not set}"
: "${MODULE_PURPOSE:?MODULE_PURPOSE not set}"
: "${MODULE_PATH:?MODULE_PATH not set}"
: "${MODULE_PUBLIC_API:?MODULE_PUBLIC_API not set}"
: "${ASSERTIONS:?ASSERTIONS not set}"
: "${UPSTREAM_ARTIFACTS:?UPSTREAM_ARTIFACTS not set}"
MODULE_DEPS="${MODULE_DEPS:-(none)}"
MODULE_SCAFFOLDS="${MODULE_SCAFFOLDS:-(none)}"

SPAWN_ENV="${CLAW_SPAWN_ENV:-$HOME/.clawborrator-spawn.env}"
IMAGE="${MODULE_BUILDER_IMAGE:-ladder99/clawborrator-worker:latest}"

if [[ ! -f "$SPAWN_ENV" ]]; then
  echo "error: $SPAWN_ENV not found" >&2
  exit 2
fi

PROMPT="$(MODULE_ID="$MODULE_ID" python3 - <<PYEOF
import os
tpl = open("$TEMPLATE").read()
out = (tpl
  .replace("{{MISSION_ID}}", os.environ["MISSION_ID"])
  .replace("{{MODULE_ID}}", os.environ["MODULE_ID"])
  .replace("{{ORCH_ROUTING}}", os.environ["ORCH_ROUTING"])
  .replace("{{MODULE_PURPOSE}}", os.environ["MODULE_PURPOSE"])
  .replace("{{MODULE_PATH}}", os.environ["MODULE_PATH"])
  .replace("{{MODULE_DEPS}}", os.environ["MODULE_DEPS"])
  .replace("{{MODULE_SCAFFOLDS}}", os.environ["MODULE_SCAFFOLDS"])
  .replace("{{MODULE_PUBLIC_API}}", os.environ["MODULE_PUBLIC_API"])
  .replace("{{ASSERTIONS}}", os.environ["ASSERTIONS"])
  .replace("{{UPSTREAM_ARTIFACTS}}", os.environ["UPSTREAM_ARTIFACTS"]))
print(out, end="")
PYEOF
)"

NAME="mission-module-${MODULE_ID}-$(date +%s)"

echo "spawning $NAME (mission=$MISSION_ID, module=$MODULE_ID, path=$MODULE_PATH)"
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
