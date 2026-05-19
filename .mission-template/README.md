# `.mission-template/`

Template files the orchestrator copies into a target repo's
`.mission/` directory when initializing a new mission.

| File          | When written     | Owner           |
|---------------|------------------|------------------|
| `state.json`  | Mission start    | Orchestrator     |
| `journal.md`  | Mission start    | Orchestrator (seed); journalist appends per phase |

Other `.mission/` files (`requirements.md`, `modules.json`,
`interfaces.json`, `scaffold-inventory.json`,
`validation-contract.json`, `checkpoint.json`, `artifacts/*`) are
created by their respective roles during the mission and don't
have starter templates.
