# worker_v1-missions-advanced

Mission toolkit for **greenfield, multi-module, multi-week
projects** with planning docs and real-system validation. Builds on
[`worker_v1-missions`](https://github.com/clawborrator/worker_v1-missions)
(feature-add for existing apps) and extends it for the project
archetype that doesn't fit the feature-add shape.

See [`docs/proposal.md`](./docs/proposal.md) for the full design
rationale.

## When to use this vs `worker_v1-missions`

| Project shape                                                                       | Use                          |
|-------------------------------------------------------------------------------------|------------------------------|
| Add a feature to an existing repo                                                   | `worker_v1-missions`         |
| Build a new system from planning docs + scaffold libs                               | `worker_v1-missions-advanced`|
| Multi-module decomposition with interface contracts between modules                 | `worker_v1-missions-advanced`|
| Multi-week implementation horizon, requires resumable orchestrator + paper trail    | `worker_v1-missions-advanced`|
| Hardware-in-the-loop validation                                                     | `worker_v1-missions-advanced`|

## What's different

Eight extensions on top of the base toolkit:

1. **Phase 0: requirements ingestion** by an `architect` role that
   reads `planning-docs/` and emits a structured `requirements.md`.
2. **Scaffold inventory** — a `scaffold-audit` role catalogs
   existing libraries the operator wants reused (e.g. `/test-repos/`).
3. **Modules + interfaces, not features.** `modules.json` declares
   modules with `depends_on` edges; `interfaces.json` declares the
   contracts between modules.
4. **Parallel module implementation** via a topological-order DAG
   executor. Independent modules build concurrently in non-
   overlapping subdirectories on per-module branches.
5. **Integrator role** wires modules together at `cmd/` after
   modules merge.
6. **Design-review role** validates UI work against the
   operator-named brand/design spec.
7. **Hardware-test role** runs the integrated binary against real
   hardware, operator-approval-gated.
8. **Journalist role** maintains an append-only `journal.md` so
   multi-week missions have a readable paper trail.

The base toolkit's `worker` / `scrutiny` / `usertest` roles carry
forward unchanged for per-module validation and any feature-add
work within modules.

## Roles overview

| Role            | Phase   | Image                                              |
|-----------------|---------|----------------------------------------------------|
| architect       | 0       | `ladder99/clawborrator-worker:latest`              |
| scaffold-audit  | 0       | `ladder99/clawborrator-worker:latest`              |
| module-builder  | 3       | `ladder99/clawborrator-worker:latest`              |
| scrutiny        | 3       | `ladder99/clawborrator-worker:latest`              |
| usertest        | 3       | `ladder99/clawborrator-worker-playwright:latest`   |
| integrator      | 3.5     | `ladder99/clawborrator-worker:latest`              |
| design-review   | 3.6     | `ladder99/clawborrator-worker-playwright:latest`   |
| hardware-test   | 3.7     | project-specific image                             |
| journalist      | after each phase | `ladder99/clawborrator-worker:latest`     |

## First-time setup

1. **`~/.clawborrator-spawn.env`** exists on this host with
   `CLAWBORRATOR_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`,
   `CLAWBORRATOR_HUB_URL` (mode 600). Same convention as
   `worker_v1-missions`.
2. **Docker available** with `/proc` + `/sys` readable.
3. **The target repo's PAT** (for `REPO_PAT`) has push access.
4. **Planning docs and scaffold libraries** organized in known
   paths the orchestrator can hand to architect / scaffold-audit
   workers (the orchestrator asks for these in Phase 0).

## Usage (orchestrator-driven)

The orchestrator agent reads [`CLAUDE.md`](./CLAUDE.md). You as
the operator interact via:

1. Initial goal description + paths to planning docs / scaffold
   libs / target repo.
2. Approval gates at the end of Phase 0 (requirements + modules
   + scaffold inventory) and before Phase 3.7 (hardware test).
3. Whatever clarifying questions the orchestrator routes via
   `mcp__clawborrator__ask_question`.

You do NOT directly invoke `bin/spawn-*.sh` — those are the
orchestrator's tools, not yours.

See [`docs/quickstart.md`](./docs/quickstart.md) for the
end-to-end walkthrough.

## Mission state

Every mission keeps its state under `.mission/` in the **target
repo's root** (so it travels with the deliverable, survives
orchestrator restarts, and ends up in the commit history):

```
.mission/
  requirements.md          Phase 0 output (architect)
  scaffold-inventory.json  Phase 0 output (scaffold-audit)
  modules.json             Phase 1 output (orchestrator + operator)
  interfaces.json          Phase 1 output (orchestrator + operator)
  validation-contract.json Phase 2 output (orchestrator)
  state.json               Current phase + cursor + completed modules
  checkpoint.json          Crash-safe resumption marker
  journal.md               Append-only narrative (journalist)
  artifacts/
    <module>-design.md     Per-module design notes
    <module>-handoff-N.json
    ...
```

Schemas for each JSON file are in [`schemas/`](./schemas/).

## Handoff format

Carries forward from `worker_v1-missions`. Every role submits via
`mcp__clawborrator__submit_handoff` with:

```json
{
  "missionId":         "<correlation-id>",
  "fromRole":          "architect" | "scaffold-audit" | "module-builder" | ...,
  "featureId":         "<module-id or phase-tag>",
  "status":            "completed" | "partial" | "failed",
  "completed":         ["bullet of what was done", ...],
  "skipped":           [{"item": "x", "reason": "y"}, ...],
  "commandsRun":       [{"cmd": "...", "exitCode": 0, "stdoutTail": "..."}, ...],
  "issues":            ["bug found at ...", ...],
  "proceduresHonored": ["1", "2", ...]
}
```

## See also

- [`docs/proposal.md`](./docs/proposal.md) — full design rationale
- [`docs/quickstart.md`](./docs/quickstart.md) — operator walkthrough
- [`worker_v1-missions`](https://github.com/clawborrator/worker_v1-missions)
  — the base toolkit this extends
- [`worker_v1`](https://github.com/clawborrator/worker_v1) — base
  image + ephemeral-worker pattern
- [`channel_v1`](https://github.com/clawborrator/channel_v1) — the
  `submit_handoff` MCP tool implementation
