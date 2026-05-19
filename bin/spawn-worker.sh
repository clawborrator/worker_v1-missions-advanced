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

# Note: we do NOT check `[[ -f "$SPAWN_ENV" ]]` here. When this
# script runs inside an orchestrator container, $SPAWN_ENV is a
# HOST-side path that docker daemon resolves separately. The local
# fs check would always fail. If the path is wrong, docker run
# below errors clearly.

# Render the prompt template using bash builtin substitution.
# Pure bash, no python/perl dependency. Placeholders are literal
# {{NAME}} strings, no regex; safe substitution.
PROMPT=$(< "$TEMPLATE")
PROMPT="${PROMPT//"{{MISSION_ID}}"/$MISSION_ID}"
PROMPT="${PROMPT//"{{FEATURE_ID}}"/$FEATURE_ID}"
PROMPT="${PROMPT//"{{ORCH_ROUTING}}"/$ORCH_ROUTING}"
PROMPT="${PROMPT//"{{FEATURE_SPEC}}"/$FEATURE_SPEC}"
PROMPT="${PROMPT//"{{ASSERTIONS}}"/$ASSERTIONS}"

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
