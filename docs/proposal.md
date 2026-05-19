# Proposal: an advanced mission toolkit for greenfield, multi-module projects

**Status:** Design rationale for `worker_v1-missions-advanced`.
**Scope:** A generic mission toolkit that handles greenfield,
multi-module engineering projects with substantial planning docs
and real-system validation.

---

## 1. The project archetype this toolkit serves

The current `worker_v1-missions` is built for "add features to an
existing application." This toolkit serves a different shape:

- **Greenfield system**, not feature-add. There is no existing repo
  with a code style to match; the deliverable IS a new repo.
- **Multi-document requirements** living in conversation logs,
  design specs, and library docs. Often >100KB of prose to digest
  before any code is written.
- **Multiple independent modules** that compose into one system.
  Most pairs of modules don't touch the same files, so they can
  build in parallel.
- **Pre-existing scaffold libraries** that should be reused, not
  rebuilt. The mission has to be aware of them.
- **Real-system validation**, not just unit tests. Software-only
  scrutiny can miss issues that only show up against live
  hardware, third-party services, or production-shape data.
- **Multi-week implementation horizon**, with sessions across many
  days. Mission state has to be crash-safe and resumable, including
  by a fresh orchestrator that wasn't around for earlier phases.
- **Design or compliance specs** matter. A brand/visual spec, an
  RFC, or a regulatory requirement constrains implementation.

Concrete examples of projects fitting this shape:

- A new microservice with REST + queue + DB + admin UI.
- A hardware-software integration that wires sensors + collector
  + analytics + dashboard.
- A migration that retires three legacy services and replaces them
  with a unified successor.
- A control system with real-time data ingest + a supervisory HMI.

They share the four-property signature: greenfield, multi-document
spec, multi-module decomposition, real-system validation.

---

## 2. What `worker_v1-missions` already nails

Carry forward, don't re-invent:

- **Orchestrator + ephemeral workers** topology. The long-lived
  orchestrator plans + dispatches; workers spawn as docker
  containers, do one bounded job, submit a structured handoff,
  self-terminate. Channel routing via clawborrator.
- **Structured handoffs** via `mcp__clawborrator__submit_handoff`
  with `status / completed / skipped / commandsRun / issues /
  proceduresHonored`.
- **State files** in `.mission/`: `features.json`,
  `validation-contract.json`, `state.json`.
- **Recovery rules** (max 3 respawns, scrutiny vs usertest
  disagreement protocol).
- **Two-tier validation**: scrutiny (code + tests) + usertest
  (behavior in a browser).
- **Spawn-script + prompt-template** pattern per role, easy to
  extend.

---

## 3. Gaps when applied to projects at this scale

### G1. No requirements-ingestion phase

The current orchestrator interviews the operator via
`ask_question` to scope features. That works when the operator
already holds the scope in their head. For projects at this scale,
the scope is distributed across many planning docs (often >100KB).
Asking the operator to verbalize all of it is the wrong tool. We
need an **Architect** role that reads `planning-docs/` and emits a
structured requirements artifact the operator then reviews.

### G2. "Features" is the wrong unit of work

In a feature-add app, a feature is one user-visible behavior. In a
greenfield system, the work is **modules** with **interfaces
between them**. `features.json` is replaced by
`modules.json` + `interfaces.json`.

A module spec carries: id, purpose, public API, dependencies on
other modules, expected file layout. An interface spec carries:
the Go-interface (or equivalent typed contract) every implementing
module must honor.

### G3. No parallel module implementation

`worker_v1-missions` enforces "serial features, no concurrent
writes." Correct for features on one repo because of merge
conflicts. Wrong for independent modules in a fresh monorepo where
`pkg/foo/`, `pkg/bar/`, `pkg/baz/` don't touch each other. The
toolkit should support **controlled parallelism**: workers writing
in non-overlapping subdirectories on per-module branches, with a
later integration phase that merges.

### G4. No scaffold/library awareness

The orchestrator doesn't know about pre-existing libraries the
operator wants reused. Workers reimplement what's already there.
We need a **scaffold inventory** phase that catalogs existing
libraries (path, purpose, tested/untested, bug fixes applied) and
a worker prompt template that lists them upfront.

### G5. No knowledge-artifact propagation

When the architect writes a cross-cutting design note that future
module-builders need to read (e.g. an event-flow diagram), no
existing mechanism points workers at upstream artifacts. We need
a `.mission/artifacts/` convention with explicit references from
`modules.json`.

### G6. No hardware/integration-test role

Scrutiny is static checks; usertest is browser-driven. Neither
covers "boot the binary against the real system and verify
end-to-end behavior." Add a **hardware-test** role that runs
against a designated test host or staging environment, gated
behind explicit operator approval (you don't want a runaway
worker driving real actuators, production data, or paid services
unsupervised).

### G7. No design-compliance role

UI work in many projects has to match a brand or design system
spec (color tokens, type scale, component patterns). Scrutiny does
code review but not "does this component match the spec." Add a
**design-review** role that diffs rendered output against the
design system spec.

### G8. Mission-journal gap

`state.json` records what completed. It does not record decisions,
deviations, blockers, or the reasoning behind respawns. For
multi-week missions this paper trail matters more than the state
machine. Need an append-only `.mission/journal.md` that every role
contributes to.

### G9. Resumable orchestrator

Multi-week missions span operator absences. The orchestrator might
restart between phases. Need an explicit `.mission/checkpoint.json`
that captures "I am in phase X, last action was Y, next action is
Z" so a fresh orchestrator can resume without re-asking the
operator anything.

### G10. Inter-worker coordination

Sometimes Worker A blocks on a decision only Worker B understands
(typically interface ambiguity). Routing through orchestrator
works but adds latency. Optional capability: workers can route
directly to a named peer with a scoped question (and the
orchestrator gets a notification).

---

## 4. Proposed roles (additions to the existing three)

| Role            | Job                                                                                                   | Image                                              |
|-----------------|-------------------------------------------------------------------------------------------------------|---------------------------------------------------|
| architect       | Reads `planning-docs/`, produces `requirements.md` + suggests `modules.json` + `interfaces.json`.     | `ladder99/clawborrator-worker:latest`             |
| scaffold-audit  | Surveys `/test-repos/` (or any operator-named existing libraries). Emits `scaffold-inventory.json`.   | `ladder99/clawborrator-worker:latest`             |
| module-builder  | Greenfield variant of worker. Builds one module in a scoped subdir/branch from `modules.json`.        | `ladder99/clawborrator-worker:latest`             |
| integrator      | After modules merged, wires them together at `cmd/`. Writes the entry point + config plumbing.        | `ladder99/clawborrator-worker:latest`             |
| hardware-test   | Boots the integrated binary against real hardware. Operator-approval-gated.                           | custom image (depends on hardware-side tooling)   |
| design-review   | Compares rendered UI against the brand/visual spec. Emits compliance report.                          | `ladder99/clawborrator-worker-playwright:latest`  |
| journalist      | After every phase completes, summarizes the phase into `.mission/journal.md`.                         | `ladder99/clawborrator-worker:latest`             |

Existing roles (`worker`, `scrutiny`, `usertest`) carry forward for
feature-add work and for the validation pass on individual
modules.

---

## 5. Proposed phases

The existing toolkit has Phases 1-4 (plan, validation contract,
execution loop, finalize). Insert before and within:

**Phase 0: ingest.**
1. `architect` reads `planning-docs/` (and any operator-named
   reference materials). Produces `requirements.md` (structured)
   and a draft `modules.json` + `interfaces.json`.
2. `scaffold-audit` surveys `/test-repos/` or other operator-named
   library paths. Produces `scaffold-inventory.json`.
3. Orchestrator presents the artifacts to the operator via
   `ask_question` for approval/revision. Iterates until accepted.

**Phase 1 (revised): scope.** Now means "lock the modules +
interfaces", not "interview for features."

**Phase 2 (revised): validation contract.** Same shape, but
assertions are per-module not per-feature; and each module's
assertions split into `software` and `hardware` validators.

**Phase 3 (revised): parallel module implementation.**
1. Per module, spawn `module-builder` on a dedicated git branch.
2. Modules with no shared dependencies run in parallel (orchestrator
   spawns N at once, awaits N handoffs).
3. Each module gets `scrutiny` + relevant validator (`usertest` for
   UI modules, `hardware-test` for hardware-touching modules,
   nothing extra for library modules).

**Phase 3.5: integration.** After all modules merged to main,
`integrator` writes `cmd/main.go` (or equivalent) and config
plumbing. Single worker, serial.

**Phase 3.6: design review (UI-bearing missions only).**
`design-review` boots the UI, captures screenshots, compares
against the operator-named design spec. Failures route to a UI-module
respawn.

**Phase 3.7: hardware test (hardware-bearing missions only).**
Operator approves before fire. `hardware-test` runs scripted
exercises against the real rig. Failures route to whichever module
the failure mode implicates.

**Phase 4 (revised): finalize.** Same shape, but the mission
report includes a list of artifacts (requirements, modules,
interfaces, journal, scaffold inventory) so the operator gets a
durable trail.

---

## 6. Mechanics

### State files (`.mission/`)

```
.mission/
  requirements.md          # Phase 0 output
  modules.json             # locked after Phase 1
  interfaces.json          # locked after Phase 1
  scaffold-inventory.json  # locked after Phase 0
  validation-contract.json # locked after Phase 2
  state.json               # current phase + cursor
  checkpoint.json          # crash-safe resumption marker
  journal.md               # append-only narrative
  artifacts/
    <module>-design.md     # per-module design notes
    <module>-handoff-N.json
    ...
```

### Parallelism semantics

`modules.json` declares each module's `depends_on: []`. The
orchestrator computes a topological order. All modules whose
dependencies are satisfied get spawned in the same wave. The wave
completes (every worker's handoff arrives) before the next wave
begins. This is the classic "DAG executor" pattern, not a
free-for-all.

### Knowledge-artifact propagation

Every worker prompt template gets a new section
`UPSTREAM_ARTIFACTS` that lists the files the orchestrator wants
this worker to read first. The orchestrator generates this list
from `modules.json` + `interfaces.json` per worker.

### Mission journal

After each phase, the `journalist` role spawns, reads the recent
handoffs + state changes, and appends a paragraph or two of
narrative. Operator gets a readable log instead of having to
piece together JSON files.

### Resumability

After every state transition, orchestrator writes
`checkpoint.json` with `{phase, cursor, lastHandoff, nextAction}`.
On startup, orchestrator reads checkpoint and continues from
`nextAction` if `state.json` matches. Mismatch → orchestrator asks
operator to confirm before proceeding.

### Inter-worker comms (optional v2)

Workers can `mcp__clawborrator__route_to_peer` with
`mode="ask"` if their prompt template explicitly allows it,
naming the allowed peers. Default: only the orchestrator.

---

## 7. Open questions before building

1. **Module-builder branch strategy.** Per-module branches that get
   merged in waves vs. per-module subdirectories on main with no
   branching at all. Per-module branches add merge overhead but
   isolate failed work. Per-module subdirs on main are simpler but
   make rollback messier.
2. **Hardware-test image.** Is there a standard worker image with
   the right hardware-side tooling, or does each project bring its
   own? Probably project-specific; the toolkit should provide a
   template not a single image.
3. **Design-review concreteness.** Comparing rendered output to a
   design spec is fuzzy. Probably need: take screenshots, run
   color-palette diff, run typography spot-checks, route subjective
   judgment to the operator with screenshots attached.
4. **Operator interaction surface.** With seven roles + multi-phase
   loops, the operator could drown in handoff notifications.
   Probably need a "quiet mode" where journalist's per-phase
   summary is the only inbound, with a sidecar URL to see full
   detail.
5. **Existing `worker_v1-missions` reuse.** Build advanced as a
   FORK or as a SUPERSET that uses missions as a dependency? Fork
   means clean slate but duplication; superset means shared
   evolution but the missions repo grows in scope. Lean toward
   superset.

---

## 8. The validation gate

The bar for this toolkit's correctness is: can it take a
greenfield project (planning docs + scaffold libs + a goal
statement) all the way to a working deliverable with the
operator's role limited to approvals and design judgments rather
than implementation? Any project at the archetype this toolkit
serves should pass that test.
