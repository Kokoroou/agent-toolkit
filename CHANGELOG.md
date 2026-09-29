# Changelog

## [0.4.1](https://github.com/Kokoroou/agent-toolkit/compare/v0.4.0...v0.4.1) (2026-09-29)


### Bug Fixes

* **bootstrap:** only run a smoke test the project has ([116aacb](https://github.com/Kokoroou/agent-toolkit/commit/116aacb31de54b8a25033d2ed52f4b39fadc90f3))
* **bootstrap:** only run a smoke test the project has ([71750ce](https://github.com/Kokoroou/agent-toolkit/commit/71750cebad3aeafba44d3d2f84a55a42fb933fec))
* **triage:** hand failed or oversized triage to a person instead of failing ([3419ed9](https://github.com/Kokoroou/agent-toolkit/commit/3419ed90d18dbe4ab8f991563b96840d715f6a92))

## [0.4.0](https://github.com/Kokoroou/agent-toolkit/compare/v0.3.1...v0.4.0) (2026-09-29)


### Features

* **bootstrap:** detect the project's lint, format and test tools ([1e9d55e](https://github.com/Kokoroou/agent-toolkit/commit/1e9d55e2085c010579f28b0032cbeb23a13743d3))

## [0.3.1](https://github.com/Kokoroou/agent-toolkit/compare/v0.3.0...v0.3.1) (2026-09-29)


### Bug Fixes

* **scripts:** pick gh commands by installed gh version ([1a4fdf7](https://github.com/Kokoroou/agent-toolkit/commit/1a4fdf704e234b413f9330a40491585c2ea50d55))
* **scripts:** use gh api for labels and secret listing so older gh works ([7a0dc7f](https://github.com/Kokoroou/agent-toolkit/commit/7a0dc7fea14aee5a4ebc45864a1aa8e4f3844aba))

## [0.3.0](https://github.com/Kokoroou/agent-toolkit/compare/v0.2.0...v0.3.0) (2026-09-29)


### ⚠ BREAKING CHANGES

* builds and fixes no longer start on GitHub Actions on their own. Set the repository variable AGENT_AUTO_BUILD=true (the updated caller templates read it) to restore automatic builds after triage and automatic fixes from the merge gate; callers of merge-gate.yml that keep their own fix job need `auto-fix: true`. The `agent:implement` label still builds on Actions.

### Features

* **agent-session:** sandboxed local/cloud sessions with encrypted env and rclone storage ([30b8c69](https://github.com/Kokoroou/agent-toolkit/commit/30b8c6916ea1ff89530caebec7bdd861e42c9cbc), [bf285b9](https://github.com/Kokoroou/agent-toolkit/commit/bf285b9c979d712116a560e0c1280e3b73e357f0))
* build issues on demand in Claude Code by default ([e9feba9](https://github.com/Kokoroou/agent-toolkit/commit/e9feba975f7204cd957183eacd8fd72ee8113195))
* **install:** ask whether to skip or overwrite existing project files ([4bc0afa](https://github.com/Kokoroou/agent-toolkit/commit/4bc0afa5748c3a4e099954b6cf38ac3d26f8fefc), [53c3b6e](https://github.com/Kokoroou/agent-toolkit/commit/53c3b6e0880500a1da92d8ac3241198ea65d5e56))
* **pipeline:** /pipeline:build without arguments proposes a build queue ([25231bc](https://github.com/Kokoroou/agent-toolkit/commit/25231bc8fedb9f73b19185eb666b6eb69aaf8ade))


### Bug Fixes

* **install:** stop early when not on the default branch ([30c7974](https://github.com/Kokoroou/agent-toolkit/commit/30c79743e6a5a2b220c963e7e894dcfd01273451))
* **pipeline:** use $ARGUMENTS in commands so args resolve on current Claude Code ([f7b4835](https://github.com/Kokoroou/agent-toolkit/commit/f7b483583a15a577ca1f32d5ec689dbc3191207d))
* **release:** merge duplicate changelog entries into one line ([df33ac8](https://github.com/Kokoroou/agent-toolkit/commit/df33ac865335b95f1b15075d5dfe97adc9d00066))

## [0.2.0](https://github.com/Kokoroou/agent-toolkit/compare/v0.1.0...v0.2.0) (2026-09-28)


### Features

* **install:** one-command project setup for Linux, macOS and Windows ([0b61540](https://github.com/Kokoroou/agent-toolkit/commit/0b61540adbc83a4b2a4fae91ee6dba9f2b53ad46), [fc73a93](https://github.com/Kokoroou/agent-toolkit/commit/fc73a93a14fd301d3ca9d9b0964d8793cc48d862))
* **scripts:** add upgrade.sh to upgrade installed pipeline files ([92ce93f](https://github.com/Kokoroou/agent-toolkit/commit/92ce93f2474b695bcf5497f890d838e9f3358489), [cf92af0](https://github.com/Kokoroou/agent-toolkit/commit/cf92af0250e32652f0a181dc4e976b92b8713a2a))
* **triage:** let clarification use any questioning technique, not only 5W ([cdeaa84](https://github.com/Kokoroou/agent-toolkit/commit/cdeaa84e6029b016438dc08287723f365dbc0051))
* **triage:** re-triage changed requirements, stop on cancel, up to 5 clarification rounds ([1ed15ce](https://github.com/Kokoroou/agent-toolkit/commit/1ed15ce805705f7cc9a52f6051be597f59e72b28))
* **triage:** re-triage changed requirements, stop on cancel, up to 5 rounds (5W) ([6c73de9](https://github.com/Kokoroou/agent-toolkit/commit/6c73de99f85af3b2c756e27d9b5f7872182e748f))


### Bug Fixes

* **install:** keep remembered tokens in the OS credential store ([b74b1c5](https://github.com/Kokoroou/agent-toolkit/commit/b74b1c55498271cbf36390f61c4178144ae33d1f))

## 0.1.0 (2026-09-28)


### Features

* agent-driven issue-to-release pipeline toolkit ([45c2ae5](https://github.com/Kokoroou/agent-toolkit/commit/45c2ae56299062308b51841ad7aeb5f3c031f18a))


### Bug Fixes

* **ci:** replace A && B || C shell chains flagged by shellcheck SC2015 ([8e5829d](https://github.com/Kokoroou/agent-toolkit/commit/8e5829d74783bd4d2acf2ab095fc0ebd565be8f8))
