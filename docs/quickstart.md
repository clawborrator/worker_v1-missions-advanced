# Quickstart

End-to-end walkthrough of running a mission through
`worker_v1-missions-advanced`. Assumes you've completed the
"First-time setup" section in the [README](../README.md).

## What you'll need before starting

1. **A target repo URL** + PAT with push access. The orchestrator
   commits `.mission/` state and the deliverable code here. Can be
   an empty repo; the architect + module-builders populate it.
2. **A folder of planning docs.** Markdown, conversation logs, RFCs,
   specs. Whatever the architect should ingest. Empty allowed but
   strongly discouraged for projects at this scale.
3. **Optional: a folder of scaffold libraries** to reuse rather
   than reimplement. Each subdirectory is one library; the
   scaffold-audit role catalogs them.
4. **A clawborrator session running as the orchestrator.** Two ways:
   - Locally: open this directory in Claude Code, the `.claude/`
     setup makes it read `CLAUDE.md` as the playbook.
   - Published agent: run a `worker_v1` container against this repo
     with `CLAWBORRATOR_ROUTING_NAME=missions-advanced-<your-tag>`.

## Step-by-step

### 1. Brief the orchestrator

Send a message describing the goal plus paths:

```
I want to build <one-paragraph description>.

Planning docs: /abs/path/to/planning-docs
Scaffold libs: /abs/path/to/test-repos (optional)
Target repo:   https://github.com/me/my-new-system
Mission id:    my-system-1
```

The orchestrator confirms via `ask_question` and writes
`.mission/state.json` to the target repo.

### 2. Phase 0: ingest

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

### 3. Phase 1: scope

After approval, the orchestrator computes the topological order
over `modules.json`'s `depends_on` graph. Shows you the proposed
waves:

```
Wave 1: pkg/foo, pkg/bar, pkg/baz, web/ui-mockup
Wave 2: pkg/qux, pkg/quux
Wave 3: cmd/myapp (integration)
```

You approve or revise.

### 4. Phase 2: validation contract

Orchestrator generates per-module assertions split by validator
type (scrutiny / usertest / design-review / hardware-test). It
asks you to confirm coverage, in particular that every UI-bearing
module has design-review assertions and every hardware-touching
module has hardware-test assertions.

### 5. Phase 3: parallel module implementation

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

### 6. Phase 3.5: integration

Single `integrator` worker wires modules at the entry point.
`scrutiny` + `usertest` validate the integration commit.

### 7. Phase 3.6: design review (UI-bearing missions only)

`design-review` boots the app and validates against the design
spec on color, typography, spacing, shape. Subjective assertions
surface to you via `ask_question` with screenshots attached.

### 8. Phase 3.7: hardware test (hardware-bearing missions only)

Operator-gated. The orchestrator asks via `ask_question`:
`Approve hardware test` / `Skip` / `Abort`. You approve only if
the hardware is staged, the assertions are within safe bounds,
and you accept the consequences of automated hardware interaction.

On approval, `hardware-test` runs the scripted exercises.
**Failures always escalate to you, never auto-respawn.**

### 9. Phase 4: finalize

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
