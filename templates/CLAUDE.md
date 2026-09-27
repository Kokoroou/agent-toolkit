# <Project name>

<!-- Read by every agent in the agent-toolkit pipeline (planner, implementer, reviewer).
     Keep it short and factual; the toolkit's pipeline-conventions skill covers the rest. -->

## Commands
- Install:  `npm ci`
- Lint:     `npm run lint`
- Format:   `npx prettier --write .` (check: `npx prettier --check .`)
- Test:     `npm test`
- Coverage: `npx jest --coverage`
- Build:    `npm run build`

## Architecture
<!-- 5–15 lines: main modules/directories and what lives where, data flow, key
     abstractions. Point to files, not descriptions of them. -->
- `src/` —
- `test/` —

## Conventions specific to this repo
<!-- Only what differs from the toolkit defaults (Conventional Commits, tests for every
     behaviour change, no coverage drop, develop ← agent/issue-N branches). -->
-

## Do not touch
<!-- Paths the agents must never modify, e.g. generated code, vendored deps, migrations. -->
-
