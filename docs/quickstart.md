# Quickstart

End-to-end walkthrough of running a mission through
`worker_v1-missions-advanced`. Assumes you've completed the
"First-time setup" section in the [README](../README.md).

## What you'll need before starting

1. **A target repo URL** + PAT with push access. The orchestrator
   clones this as its own `/workspace/repo`. Conventionally the
   target repo carries:
   - `planning-docs/` — input to the architect role
   - `scaffold-libs/` — input to the scaffold-audit role
   - `PROMPT.md` — the operator's mission charter
   - existing `README.md` or other operator content is fine
2. **A target host with docker** + the operator's
   `~/.clawborrator-spawn.env` file in place. The orchestrator
   container spawns worker containers laterally on this host.
3. **A local clone of `worker_v1-missions-advanced` on the target
   host.** The orchestrator bind-mounts this as its playbook;
   `bin/spawn-*.sh` and `templates/*.tmpl` need to be filesystem-
   accessible to the orchestrator.

## Step-by-step

### 1. Prep the target host

SSH to the host where the orchestrator + workers will run.

```bash
cd ~
git clone https://github.com/clawborrator/worker_v1-missions-advanced
# (The target repo will be cloned by the orchestrator container
#  itself via REPO_URL; no need to clone it on the host.)
```

Confirm prereqs: docker installed, `~/.clawborrator-spawn.env`
exists (mode 600 with all six secrets), enough disk for the
mission's commit history.

### 2. Spawn the orchestrator container

```bash
docker run -dt --rm \
  --name missions-advanced-<your-mission-tag> \
  --env-file ~/.clawborrator-spawn.env \
  -e CLAWBORRATOR_ROUTING_NAME=missions-advanced-<your-mission-tag> \
  -e MODEL=sonnet \
  -e CLAUDE_SKIP_PERMISSIONS=1 \
  -e REPO_URL=https://github.com/<owner>/<target-repo> \
  -e CLAW_SPAWN_ENV=$HOME/.clawborrator-spawn.env \
  -e CLAUDE_INITIAL_PROMPT="You are the missions-advanced orchestrator. Read /playbook/CLAUDE.md carefully — that is your playbook. Wait for the operator's mission brief before doing anything." \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $HOME/worker_v1-missions-advanced:/playbook:ro \
  ladder99/clawborrator-worker:latest
```

Notes:
- `REPO_URL` = target repo. The orchestrator's `/workspace/repo`
  IS the working repo where `.mission/state.json` lives.
- `/playbook` = host clone of this toolkit. Read-only.
- `CLAW_SPAWN_ENV` points at the HOST path of spawn-env (docker
  daemon resolves bind-mount paths from host filesystem, so
  workers' `docker run --env-file <this>` needs the host path).
- No `CLAWBORRATOR_EPHEMERAL=1`. The orchestrator is long-lived.

### 3. Brief the orchestrator

From any session with `mcp__clawborrator__route_to_peer` access:

```
route_to_peer({
  peer: "@missions-advanced-<your-mission-tag>",
  mode: "ask",
  prompt: "Begin mission <id>:
    Target repo URL: https://github.com/<owner>/<target-repo>
    Mission ID: <id>
    Goal: <one paragraph, or `read PROMPT.md`>"
})
```

The orchestrator confirms via `ask_question` and writes
`.mission/state.json` to the target repo.

### 4. Phase 0: ingest

The orchestrator spawns `architect` + `scaffold-audit` in parallel.
Each writes its artifacts to its own branch in the target repo.

The orchestrator awaits both handoffs (typically 5-15 minutes
depending on planning-docs size and scaffold count). On completion,
it presents the three artifacts via `ask_question`:

- `.mission/requirements.md`
- `.mission/modules.json` (draft)
- `.mission/interfaces.json` (draft)
- `.mission/scaffold-inventory.json`

You review. Options: `Approve` / `Revise <which artifact> with notes` /
`Abort`.

On revise, the orchestrator respawns the relevant role with your
notes as `REVISION_NOTES`. Max 2 revisions per role before
escalating.

### 5. Phase 1: scope

After approval, the orchestrator computes the topological order
over `modules.json`'s `depends_on` graph. Shows you the proposed
waves:

```
Wave 1: pkg/foo, pkg/bar, pkg/baz, web/ui-mockup
Wave 2: pkg/qux, pkg/quux
Wave 3: cmd/myapp (integration)
```

You approve or revise.

### 6. Phase 2: validation contract

Orchestrator generates per-module assertions split by validator
type (scrutiny / usertest / design-review / hardware-test). It
asks you to confirm coverage, in particular that every UI-bearing
module has design-review assertions and every hardware-touching
module has hardware-test assertions.

### 7. Phase 3: parallel module implementation

The orchestrator dispatches each wave concurrently. Per module:

- `module-builder` writes the module on its own branch in its own
  scoped subdirectory
- `scrutiny` runs against the module commit
- `usertest` runs if the module has usertest assertions
- On all-pass, the orchestrator merges the module branch into main
  and adds the module to `state.json.completedModules`

Recovery (max 3 respawns per module) is automatic. After 3 you'll
get an `ask_question` with options `Skip module / Manual / Abort`.

Wave N+1 starts only after every module in wave N is completed.

### 8. Phase 3.5: integration

Single `integrator` worker wires modules at the entry point.
`scrutiny` + `usertest` validate the integration commit.

### 9. Phase 3.6: design review (UI-bearing missions only)

`design-review` boots the app and validates against the design
spec on color, typography, spacing, shape. Subjective assertions
surface to you via `ask_question` with screenshots attached.

### 10. Phase 3.7: hardware test (hardware-bearing missions only)

Operator-gated. The orchestrator asks via `ask_question`:
`Approve hardware test` / `Skip` / `Abort`. You approve only if
the hardware is staged, the assertions are within safe bounds,
and you accept the consequences of automated hardware interaction.

On approval, `hardware-test` runs the scripted exercises.
**Failures always escalate to you, never auto-respawn.**

### 11. Phase 4: finalize

The orchestrator cross-references every assertion against the
handoff history. Generates a mission report. Routes the report to
you via `mcp__clawborrator__route_to_peer` (mode=tell).

Final state: a working repo at the target URL with `.mission/`
intact for the audit trail, plus the deliverable code.

## After every phase: the journal

The `journalist` role appends to `.mission/journal.md` after each
phase ends. Skim it weekly. For multi-week missions this is your
primary interface to mission history.

## What to do if the orchestrator gets stuck

The orchestrator escalates to you for:

- Phase 0 artifact approval
- Phase 1 module/wave approval
- Phase 2 assertion coverage confirmation
- Worker respawn limit (3) hit on any role
- Hardware-test failures
- Design-review subjective judgments
- Cycles or contradictions in modules.json

It does NOT escalate for:

- Routine worker handoffs (status=completed)
- Scrutiny/usertest failures within the 3-respawn limit
- Per-module integration of module-builder + validators

## Resuming a mission after interruption

If the orchestrator crashes or you close its session, the next
orchestrator startup:

1. Reads `.mission/checkpoint.json` from the target repo.
2. Reads `.mission/state.json` to confirm.
3. If they agree, resumes from `nextAction` automatically.
4. If they disagree, asks you to confirm before proceeding.

You don't have to brief the orchestrator again on goals, paths,
or the planning docs — all of that is in the state files.
