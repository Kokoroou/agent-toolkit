# Bảo trì agent-toolkit

Tài liệu cho **người bảo trì repo `kokoroou/agent-toolkit`**: thiết lập repo một lần,
quy trình phát triển, kiểm thử thay đổi, phát hành phiên bản và giữ tương thích cho các
dự án đang dùng.

> Chỉ muốn dùng toolkit? Xem [GETTING-STARTED.md](GETTING-STARTED.md) và
> [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md).

Mục lục:

1. [Bố cục repo](#1-bố-cục-repo)
2. [Thiết lập repo một lần](#2-thiết-lập-repo-một-lần)
3. [Môi trường phát triển](#3-môi-trường-phát-triển)
4. [Quy trình thay đổi](#4-quy-trình-thay-đổi)
5. [Kiểm thử trên repo sandbox](#5-kiểm-thử-trên-repo-sandbox)
6. [Phát hành](#6-phát-hành)
7. [Tương thích và breaking change](#7-tương-thích-và-breaking-change)
8. [Công việc định kỳ](#8-công-việc-định-kỳ)
9. [Có nên cài pipeline cho chính toolkit?](#9-có-nên-cài-pipeline-cho-chính-toolkit)

---

## 1. Bố cục repo

| Đường dẫn | Là gì | Ai dùng |
|---|---|---|
| `.github/workflows/{triage,implement,review,quality,merge-gate,release,usage-report}.yml` | Reusable workflow (`on: workflow_call`) — toàn bộ logic pipeline | Dự án gọi bằng `uses: …@v0` |
| `.github/workflows/self-test.yml` | CI của toolkit | Toolkit |
| `.github/workflows/toolkit-release.yml` | Phát hành toolkit (gọi lại `release.yml`) + dời tag major | Toolkit |
| `.claude-plugin/marketplace.json`, `plugins/pipeline/` | Marketplace + plugin Claude Code (agents, commands, skill) | Workflow agent cài qua `toolkit-marketplace`; người dùng cài tay |
| `templates/` | File bootstrap chép vào dự án (caller workflow, issue/PR template, nhãn, `CLAUDE.md`) | `scripts/bootstrap.sh` |
| `workflows/ci-doctor.md` | Workflow gh-aw | `gh aw add kokoroou/agent-toolkit/ci-doctor` |
| `scripts/bootstrap.sh`, `scripts/lint.sh` | Cài vào dự án; kiểm tra toolkit | Người dùng; CI + bạn |
| `release-please-config.json`, `.release-please-manifest.json`, `version.txt`, `CHANGELOG.md` | Cấu hình và trạng thái phát hành | release-please |
| `docs/` | Tài liệu | |

Quan hệ quan trọng cần nhớ khi sửa:

- Caller trong `templates/.github/workflows/` phải khớp input/secret của reusable workflow
  tương ứng — `scripts/lint.sh` kiểm chéo bằng actionlint.
- Tên workflow `CI` và `Agent Review` được `agent-merge-gate.yml` tham chiếu; tên file
  `ci.yml`, `agent-review.yml`, `agent-implement.yml` được dispatch khi không có App.
- Nhãn trong `templates/.github/labels.json` được các reusable workflow dùng bằng tên cứng.
- Plugin được các workflow cài bằng tên `pipeline@agent-toolkit` và gọi lệnh
  `/pipeline:<command>` — đổi tên plugin/lệnh là breaking change.

## 2. Thiết lập repo một lần

Đã làm cho `kokoroou/agent-toolkit`; ghi lại để làm lại khi chuyển repo/fork.

1. **Visibility: public.** Caller ở repo private chỉ gọi được reusable workflow của repo
   public (hoặc cùng owner với cấu hình *Access* đặc biệt), và `claude plugin marketplace add`
   / `plugin_marketplaces` clone được mà không cần PAT. Toolkit không chứa secret hay
   nghiệp vụ — đừng bao giờ commit thứ gì như vậy vào đây.
2. **[Settings → Actions → General](https://github.com/kokoroou/agent-toolkit/settings/actions) → Workflow permissions**: *Read and write permissions*
   và tick *Allow GitHub Actions to create and approve pull requests* — **trước lần push
   đầu tiên lên `main`**. Thiếu bước này release-please chỉ tạo được nhánh
   `release-please--…` mà không mở được PR (`GitHub Actions is not permitted to create or
   approve pull requests`). Sau khi bật, chạy lại run `toolkit-release` bị lỗi.
3. **[Settings → General](https://github.com/kokoroou/agent-toolkit/settings) → Pull Requests**: bật *Allow squash merging*, nên tắt merge
   commit để lịch sử `main` là chuỗi Conventional Commits sạch (release-please đọc nó).
4. **[Settings → Rules → Rulesets](https://github.com/kokoroou/agent-toolkit/settings/rules)** (repo public có sẵn trên gói Free): nên có ruleset
   cho `main` cấm force-push và xoá branch. Cẩn thận nếu bật *Require status checks*
   (`lint`): release PR do `GITHUB_TOKEN` mở **không** kích hoạt `self-test`, nên check
   không bao giờ xuất hiện và PR bị kẹt — khi đó thêm mình vào *Bypass list* (merge với
   quyền admin) hoặc cấu hình secret `AGENT_APP_ID`/`AGENT_APP_PRIVATE_KEY` cho toolkit
   (`toolkit-release.yml` truyền `secrets: inherit`, release PR mở bằng App sẽ chạy CI).
5. **Tags**: không đặt rule chặn cập nhật tag `v*` — `toolkit-release.yml` phải
   force-push tag major (`v0`, `v1`…).

## 3. Môi trường phát triển

```bash
git clone https://github.com/kokoroou/agent-toolkit && cd agent-toolkit
npm install -g @anthropic-ai/claude-code          # claude plugin validate
# actionlint: https://github.com/rhysd/actionlint (brew install actionlint / go install)
# shellcheck: brew install shellcheck / sudo apt install shellcheck
# jq:         brew install jq / sudo apt install jq
scripts/lint.sh
```

`scripts/lint.sh` kiểm tra:

1. Mọi file JSON hợp lệ.
2. `claude plugin validate --strict` cho plugin và marketplace.
3. `actionlint` cho `.github/workflows/*.yml` (kèm shellcheck cho script nhúng).
4. Caller template: thay `kokoroou/agent-toolkit/...@ref` bằng đường dẫn local rồi
   actionlint lại — bắt lỗi thiếu/sai input hoặc secret giữa caller và reusable workflow.
5. `shellcheck scripts/*.sh`.

`self-test.yml` chạy đúng script này trên mọi PR và push `main`, thêm một lần bootstrap
vào repo tạm để chắc chắn không còn `@main` sau khi ghim `--ref`.

Thử plugin đang sửa mà không cần publish:

```bash
claude --plugin-dir ./plugins/pipeline      # trong một repo dự án bất kỳ
# hoặc: claude plugin marketplace add ./ && claude plugin install pipeline@agent-toolkit
```

## 4. Quy trình thay đổi

1. Tạo branch từ `main` (`feat/...`, `fix/...`).
2. Sửa; nếu thêm/sửa input của reusable workflow thì cập nhật luôn caller trong
   `templates/.github/workflows/` và tài liệu ([ADD-TO-PROJECT.md](ADD-TO-PROJECT.md)).
3. `scripts/lint.sh` xanh trên máy.
4. Commit theo **Conventional Commits** — release-please dựa vào đó để tính version và
   viết CHANGELOG:

   | Tiền tố | Ảnh hưởng version (trước 1.0.0) | Ví dụ |
   |---|---|---|
   | `fix:` | patch | `fix(merge-gate): ignore skipped checks` |
   | `feat:` | minor | `feat(triage): add max-rounds input` |
   | `feat!:` / `BREAKING CHANGE:` | minor (do `bump-minor-pre-major`) | `feat(implement)!: rename setup input` |
   | `docs:`, `chore:`, `ci:`, `refactor:`, `test:` | không phát hành riêng | |

   Sau 1.0.0: `fix` → patch, `feat` → minor, breaking → major.
5. Mở PR vào `main`; squash-merge với tiêu đề PR là commit message đúng chuẩn.
6. Với thay đổi hành vi pipeline, kiểm thử trên sandbox trước khi merge (§5).

## 5. Kiểm thử trên repo sandbox

Lint không bắt được lỗi logic của workflow. Giữ một repo private `kokoroou/agent-sandbox`
(dựng theo [GETTING-STARTED §8](GETTING-STARTED.md#8-chạy-thử-trên-repo-sandbox)) và
trỏ nó vào branch đang phát triển:

```bash
cd ~/code/agent-sandbox
sed -i 's#\(kokoroou/agent-toolkit/\.github/workflows/[a-z-]*\.yml\)@[A-Za-z0-9._/-]*#\1@feat/my-change#' \
  .github/workflows/*.yml
# nếu sửa plugin: thêm vào các job triage/implement/review/fix
#   toolkit-marketplace: https://github.com/kokoroou/agent-toolkit.git#feat/my-change
git commit -am "ci: test agent-toolkit feat/my-change" && git push
```

Chạy các kịch bản trong [GETTING-STARTED §8.2](GETTING-STARTED.md#82-kịch-bản-nên-thử)
liên quan tới thay đổi. Nếu đổi template, chạy lại bootstrap với `--force` vào một clone
sạch của sandbox. Xong thì trả sandbox về `@main` (hoặc `@v0`).

## 6. Phát hành

Tự động bằng `toolkit-release.yml` mỗi khi push `main`:

1. release-please (qua reusable `release.yml` với `release-please-config.json`) mở hoặc
   cập nhật **release PR** `chore(main): release X.Y.Z`, tăng version ở `version.txt`,
   `.release-please-manifest.json`, `plugins/pipeline/.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json` (hai chỗ) và viết `CHANGELOG.md`.
2. Bạn review CHANGELOG trong PR đó rồi merge.
3. release-please tạo tag `vX.Y.Z` + GitHub Release; job `major-tag` force-push tag di
   động `vX` (vd `v0`) về cùng commit. Mọi dự án ghim `@v0` nhận bản mới ngay ở run kế tiếp.

Lưu ý:

- Chỉ merge PR do **github-actions** mở (nhãn `autorelease: pending`, mô tả do
  release-please sinh). Đừng tự mở PR từ nhánh `release-please--…`: release-please không
  nhận ra PR đó nên sẽ không tạo tag/release khi merge.
- **Không sửa tay** version trong các file kể trên — release-please quản lý.
- Muốn ép version cụ thể: commit rỗng có footer `Release-As: 1.0.0`
  (`git commit --allow-empty -m "chore: release 1.0.0" -m "Release-As: 1.0.0"`).
- Lên **1.0.0** sẽ tạo tag major mới `v1`; `v0` đứng yên ở bản 0.x cuối. Nhớ cập nhật
  ví dụ `@v0` trong README và docs, và `--ref` khuyến nghị trong
  [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md).
- Release lỗi (tag sai): xoá GitHub Release + tag `vX.Y.Z`, sửa `.release-please-manifest.json`
  về version trước qua PR, rồi merge lại. Tag major tự đúng lại ở release kế tiếp, hoặc
  dời tay: `git tag -f v0 v0.1.0 && git push -f origin refs/tags/v0`.

## 7. Tương thích và breaking change

Dự án ghim tag di động nên **mọi thay đổi trên `main` sau khi phát hành đến tay người
dùng mà họ không cần làm gì**. Coi các thứ sau là breaking (cần `!` và ghi chú nâng cấp
trong commit body):

- Đổi tên/xoá input, output hoặc secret của reusable workflow; đổi default làm thay đổi
  hành vi (vd `merge-method`, `block-labels`).
- Thêm input `required: true`.
- Đổi tên nhãn, tên status `agent/review`, tên branch `agent/issue-N`, marker ẩn trong comment.
- Đổi tên plugin, tên lệnh `/pipeline:*`, schema JSON mà workflow đọc từ Claude.
- Tăng quyền (`permissions:`) mà caller phải cấp thêm.

Không breaking: thêm input tuỳ chọn có default giữ hành vi cũ, sửa prompt/agent mà không
đổi định dạng đầu ra, sửa lỗi.

Plugin được cài từ `toolkit-marketplace` (mặc định nhánh mặc định, tức `main`), **không**
theo tag mà dự án ghim. Vì vậy thay đổi plugin phải tương thích ngược với các reusable
workflow của mọi tag major còn được dùng, hoặc dự án phải ghim `#vX` cho marketplace.

## 8. Công việc định kỳ

- **Cập nhật action**: `anthropics/claude-code-action`, `actions/*`,
  `googleapis/release-please-action`, `actions/create-github-app-token` — theo dõi
  release, đổi version, lint, thử sandbox. (Có thể bật Dependabot cho `github-actions`
  trong chính repo này.)
- **Model mặc định**: các input `model` mặc định là alias (`sonnet`) nên tự theo model
  mới; kiểm tra khi Anthropic đổi alias.
- **ci-doctor**: so với upstream `githubnext/agentics` khi gh-aw có thay đổi lớn.
- **Tài liệu**: khi thêm input/nhãn/workflow, cập nhật [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md),
  [ARCHITECTURE.md](ARCHITECTURE.md), README và thông báo cuối của `bootstrap.sh`.

## 9. Có nên cài pipeline cho chính toolkit?

**Không nên cài toàn bộ pipeline tự động.** Lý do:

| Vấn đề | Chi tiết |
|---|---|
| Repo **public** | Ai cũng mở được issue/comment → triage và build tốn tiền Claude + phút Actions theo người lạ, và nội dung issue là bề mặt prompt-injection. `allowed-bots: "*"` và cấu hình mặc định được thiết kế cho repo private. |
| Thay đổi chủ yếu là workflow | Agent phải sửa `.github/workflows/` → App cần quyền *Workflows* ghi. Một PR tự merge sai sẽ, sau release kế tiếp, lan tới **mọi** dự án ghim `@v0`. Rủi ro của toolkit luôn là `risk:high`, tức sẽ không bao giờ được auto-merge — tự động hoá không đem lại gì. |
| Mô hình branch khác | Toolkit phát hành trực tiếp từ `main` (không có `develop`), và không có test/coverage thực thi được: `quality.yml` chỉ gate được bằng lint, không kiểm được hành vi workflow. |
| Tự tham chiếu | Pipeline chạy code của chính toolkit trong lúc agent sửa code đó; lỗi ở `merge-gate.yml` có thể chặn chính PR sửa nó. |

Nên dùng thay thế:

- **Plugin khi làm tay** (`/pipeline:plan-feature`, `/pipeline:review-pr`) để lập kế hoạch và
  tự review PR của mình — không cần secret hay workflow.
- Nếu muốn một phần tự động: chỉ **`agent-review.yml`** (review khi *người bảo trì* gắn
  nhãn `agent`, không merge gate) và có thể **`agent-triage.yml`** với `dispatch-on-ready`
  để trống (chỉ gắn nhãn, không build). Cả hai cần secret Claude trong repo; hãy giới hạn
  trigger triage cho issue của collaborator trước khi bật trên repo public.
- Kiểm thử thật vẫn là repo sandbox (§5) — đó mới là nơi "ăn thử" pipeline an toàn.
