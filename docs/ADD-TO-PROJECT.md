# Thêm agent-toolkit vào một dự án

Hướng dẫn từng bước để cài pipeline agent vào **một repo dự án** (mới hoặc đã có code).
Làm lại toàn bộ tài liệu này cho mỗi repo.

> Lần đầu dùng toolkit? Làm [GETTING-STARTED.md](GETTING-STARTED.md) trước: cài `gh`,
> lấy thông tin đăng nhập Claude, tạo GitHub App (một lần cho mọi dự án).

Mục lục:

0. [Checklist](#0-checklist)
1. [Chuẩn bị repo](#1-chuẩn-bị-repo)
2. [Chạy bootstrap](#2-chạy-bootstrap)
3. [Sửa workflow cho stack của dự án](#3-sửa-workflow-cho-stack-của-dự-án)
4. [Viết `CLAUDE.md`](#4-viết-claudemd)
5. [Thêm secrets](#5-thêm-secrets)
6. [Cấu hình Settings của repo](#6-cấu-hình-settings-của-repo)
7. [Chọn default branch](#7-chọn-default-branch)
8. [Commit và kiểm tra](#8-commit-và-kiểm-tra)
9. [Tuỳ chọn: Projects, Dependabot, ci-doctor, release](#9-tuỳ-chọn)
10. [Ghim và nâng cấp phiên bản toolkit](#10-ghim-và-nâng-cấp-phiên-bản-toolkit)
11. [Vận hành hằng ngày](#11-vận-hành-hằng-ngày)
12. [Xử lý sự cố](#12-xử-lý-sự-cố)

---

## 0. Checklist

- [ ] Repo có ít nhất một commit, lint/test chạy được trên máy
- [ ] `scripts/bootstrap.sh` đã chạy (file + nhãn + branch `develop`)
- [ ] Các khối `edit for your stack` đã sửa trong `ci.yml`, `agent-implement.yml`, `agent-merge-gate.yml`
- [ ] `CLAUDE.md` đã điền
- [ ] Secret Claude (+ App) đã thêm
- [ ] Workflow permissions: *Read and write* + *Allow GitHub Actions to create and approve pull requests*
- [ ] Caller workflow nằm trên **default branch**
- [ ] Thử một issue nhỏ đi hết vòng

## 1. Chuẩn bị repo

- Repo phải tồn tại trên GitHub và đã clone về máy. Với repo mới tinh:

  ```bash
  gh repo create my-project --private --clone && cd my-project
  # tạo khung dự án, ít nhất một test chạy được, rồi:
  git add -A && git commit -m "chore: initial commit" && git push -u origin HEAD
  ```

  Bootstrap tạo `develop` từ default branch nên repo cần có ít nhất một commit.
- Dự án nên có sẵn lệnh **lint**, **format check**, **test**, và nếu được thì **coverage**.
  Pipeline chỉ an toàn bằng bộ test của bạn: agent chỉ được merge khi CI xanh.
- Nếu repo đã có `.github/workflows/ci.yml`, `CLAUDE.md`, issue template…: bootstrap
  **giữ nguyên** file đã có (trừ khi dùng `--force`); bạn cần tự gộp nội dung (xem §2.3).

## 2. Chạy bootstrap

### 2.1 Lệnh

```bash
git clone https://github.com/kokoroou/agent-toolkit /tmp/agent-toolkit
cd ~/code/my-project && gh auth status          # gh phải đăng nhập, có quyền admin repo
/tmp/agent-toolkit/scripts/bootstrap.sh ~/code/my-project --ref v0
```

| Tuỳ chọn | Ý nghĩa |
|---|---|
| `--ref <ref>` | Ghim mọi `uses: kokoroou/agent-toolkit/...@<ref>`. Khuyến nghị `v0` (tag di động của bản 0.x hiện tại; `v1` khi toolkit lên 1.0.0). `main` = luôn mới nhất, chỉ dùng cho sandbox. Mặc định: `main`. |
| `--force` | Ghi đè file đã có trong repo dự án. |
| `--no-labels` | Không tạo nhãn / branch `develop` (khi chưa có `gh` hoặc đã tạo rồi). |

### 2.2 Bootstrap làm gì

1. Chép từ `templates/` sang repo dự án:

   | File | Vai trò |
   |---|---|
   | `.github/workflows/ci.yml` | CI (tên `CI`): lint, format, test, coverage, tiêu đề PR, Semgrep, Gitleaks |
   | `.github/workflows/agent-triage.yml` | Triage issue khi mở/sửa/comment, quét 6 giờ/lần |
   | `.github/workflows/agent-implement.yml` | Build agent; chạy khi triage dispatch hoặc khi gắn nhãn `agent:implement` |
   | `.github/workflows/agent-review.yml` | Review PR mang nhãn `agent` (tên `Agent Review`) |
   | `.github/workflows/agent-merge-gate.yml` | Chạy sau `CI`/`Agent Review`: merge, gửi đi sửa, hoặc chặn |
   | `.github/workflows/release.yml` | release-please khi push `main` |
   | `.github/workflows/agent-usage-report.yml` | Báo cáo phút Actions + chi phí Claude hằng tuần |
   | `.github/ISSUE_TEMPLATE/{feature,bug,config}.yml` | Template issue có cấu trúc, tắt issue trống |
   | `.github/pull_request_template.md` | Template PR |
   | `.github/dependabot.yml` | Cập nhật dependency, PR vào `develop` |
   | `CLAUDE.md` | Khung hướng dẫn dự án cho agent |

2. Thay `@main` trong các dòng `uses:` bằng `--ref`.
3. Tạo ~24 nhãn (`needs-triage`, `agent`, `risk:high`, `size:M`…) — chạy lại an toàn.
4. Tạo branch `develop` từ default branch nếu chưa có.

### 2.3 Repo đã có sẵn file

Bootstrap in danh sách `Kept existing`. Với từng file:

- **`ci.yml` riêng**: có thể giữ CI cũ, nhưng workflow phải tên **`CI`** (merge gate và
  vòng fix tìm theo tên này), có `workflow_dispatch:` và chạy trên `pull_request` vào
  `develop`. Hoặc đổi `ci-workflow` / `workflows: [...]` trong caller cho khớp tên CI cũ.
- **`CLAUDE.md` có sẵn**: thêm các mục *Commands*, *Architecture*, *Do not touch* từ
  `/tmp/agent-toolkit/templates/CLAUDE.md`.
- **Issue template riêng**: giữ được, nhưng template phải gắn nhãn `needs-triage` và nên
  có các mục Goal / Constraints / Acceptance criteria để triage chấm điểm tốt.

## 3. Sửa workflow cho stack của dự án

Template mặc định cho **Node + Jest + Prettier + ESLint**. Tìm các khối
`# ── edit for your stack ──` và sửa.

### 3.1 `ci.yml`

| Input | Ý nghĩa |
|---|---|
| `setup-command` | Cài dependency (chạy trước mọi bước) |
| `lint-command`, `format-check-command` | Để trống = bỏ qua bước đó |
| `test-command` | Chạy test. Để trống nếu `coverage-command` đã chạy test (tiết kiệm phút) |
| `coverage-command` | **Dòng cuối stdout phải chứa số phần trăm** (vd `87.3` hoặc `87.3%`; lấy số cuối cùng trên dòng). Mọi output khác chuyển sang stderr bằng `>&2`. Để trống = không gate coverage |
| `coverage-tolerance` | Cho phép giảm bao nhiêu điểm phần trăm so với `develop` (`"0"` = không được giảm) |
| `enable-security`, `semgrep-config` | Semgrep (chỉ báo finding mới so với base) + Gitleaks |
| `enable-pr-title-check` | Tiêu đề PR phải theo Conventional Commits |

Cần thêm bước cài runtime (setup-node/python/go) thì đưa vào `setup-command`; runner
`ubuntu-latest` đã có sẵn Node, Python, Go, Java ở phiên bản phổ biến.

### 3.2 `agent-implement.yml` và job `fix` trong `agent-merge-gate.yml`

| Input | Ý nghĩa |
|---|---|
| `setup-command` | Như CI — để agent chạy được test |
| `extra-allowed-tools` | Các lệnh shell agent được phép chạy, dạng `Bash(<lệnh>)` hoặc `Bash(<tiền tố>:*)`. **Thiếu lệnh nào thì agent không chạy được lệnh đó** (không tự test được → PR dễ đỏ) |
| `model`, `max-turns`, `timeout-minutes` | Giới hạn chi phí / thời gian mỗi run |
| `ci-dispatch-workflow`, `review-dispatch-workflow` | Chỉ dùng khi **không** có App; giữ nguyên nếu không đổi tên file |

Hai chỗ (`agent-implement.yml` và job `fix`) phải **giống nhau** về `setup-command` và
`extra-allowed-tools`.

Trong job `gate` của `agent-merge-gate.yml`:

| Input | Ý nghĩa |
|---|---|
| `smoke-command` | Chạy trên `develop` ngay sau merge; fail → PR revert tự động. Để trống = bỏ qua |
| `required-statuses` | Mặc định `agent/review` (status do reviewer ghi) |
| `required-checks` / `ignore-checks` | Tên check run bắt buộc / bỏ qua |
| `block-labels` | Mặc định `needs-human,risk:high,do-not-merge,wip` |
| `merge-method` | Mặc định `squash` |

### 3.3 Ví dụ theo stack

**Python (pytest + ruff):**

```yaml
# ci.yml
setup-command: pip install -e ".[dev]"
lint-command: ruff check .
format-check-command: ruff format --check .
coverage-command: >-
  pytest --cov=src --cov-report=term >&2 &&
  coverage report --format=total
# agent-implement.yml + fix job
setup-command: pip install -e ".[dev]"
extra-allowed-tools: "Bash(pip install:*),Bash(pytest:*),Bash(ruff:*),Bash(python -m:*),Bash(mypy:*)"
# gate job
smoke-command: pytest -m smoke
```

**Go:**

```yaml
# ci.yml
setup-command: go mod download
lint-command: go vet ./...
format-check-command: test -z "$(gofmt -l .)"
coverage-command: >-
  go test -coverprofile=c.out ./... >&2 &&
  go tool cover -func=c.out | tail -1 | awk '{print $3}'   # "84.6%" cũng được chấp nhận
# agent-implement.yml + fix job
setup-command: go mod download
extra-allowed-tools: "Bash(go build:*),Bash(go test:*),Bash(go vet:*),Bash(gofmt:*),Bash(go mod:*)"
# gate job
smoke-command: go build ./... && go test -run Smoke ./...
```

**Node với pnpm:**

```yaml
setup-command: corepack enable && pnpm install --frozen-lockfile
extra-allowed-tools: "Bash(pnpm install:*),Bash(pnpm run:*),Bash(pnpm test:*),Bash(pnpm exec:*)"
```

Kiểm tra `coverage-command` trên máy trước khi commit — dòng cuối phải là một số:

```bash
bash -c '<coverage-command của bạn>' 2>/dev/null | tail -1   # vd: 84.61
```

### 3.4 Các tuỳ chỉnh khác thường dùng

- `agent-triage.yml`: `max-rounds` (số vòng hỏi lại), `auto-implement-max-size`
  (`XS|S|M|L`; lớn hơn thì chờ người gắn `agent:implement`), bỏ `dispatch-on-ready`
  nếu muốn luôn tự quyết định issue nào được build.
- `agent-usage-report.yml`: `minutes-budget`, `cost-budget-usd` theo ngân sách của bạn.
- Branch tích hợp khác `develop`: đổi `base-branch`, `baseline-branch` và `branches:`
  trong mọi caller cho khớp.

## 4. Viết `CLAUDE.md`

`CLAUDE.md` ở root repo được planner, implementer và reviewer đọc ở mọi run. Đây là
nơi quan trọng nhất để agent làm đúng ý bạn. Giữ ngắn, cụ thể:

- **Commands**: đúng các lệnh install/lint/format/test/coverage/build — khớp với
  `extra-allowed-tools`, nếu không agent sẽ thử lệnh mà nó không được phép chạy.
- **Architecture**: 5–15 dòng: thư mục nào chứa gì, luồng dữ liệu, abstraction chính.
  Trỏ tới file, không mô tả dài.
- **Conventions**: chỉ những gì khác mặc định của toolkit (Conventional Commits, test cho
  mọi thay đổi hành vi, coverage không giảm). Ví dụ: "dùng `Result<T>` thay vì throw",
  "API mới phải có OpenAPI spec trong `docs/api/`".
- **Do not touch**: đường dẫn agent không được sửa (code sinh tự động, vendored,
  migration đã chạy, `.github/workflows/`…).

## 5. Thêm secrets

**Repo → Settings → Secrets and variables → Actions → New repository secret**
(`https://github.com/<owner>/<repo>/settings/secrets/actions`), hoặc bằng CLI
(chạy trong thư mục repo):

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN          # dán token, Enter, Ctrl-D — hoặc ANTHROPIC_API_KEY
gh secret set AGENT_APP_ID --body 123456
gh secret set AGENT_APP_PRIVATE_KEY < ~/Downloads/kokoroou-agent.*.private-key.pem
gh secret set PROJECT_TOKEN                    # chỉ khi dùng Projects (§9.1)
gh secret list                                 # kiểm tra
```

| Secret | Bắt buộc | Ghi chú |
|---|---|---|
| `ANTHROPIC_API_KEY` *hoặc* `CLAUDE_CODE_OAUTH_TOKEN` | ✔ | Xem [GETTING-STARTED §4](GETTING-STARTED.md#4-chuẩn-bị-thông-tin-đăng-nhập-claude) |
| `AGENT_APP_ID`, `AGENT_APP_PRIVATE_KEY` | khuyến nghị | App phải **được cài vào repo này** ([GETTING-STARTED §5.3](GETTING-STARTED.md#53-cài-app-vào-repo)) |
| `PROJECT_TOKEN` | nếu dùng Projects | classic PAT, scope `project` + `repo` |
| `GITLEAKS_LICENSE` | chỉ repo thuộc organization | đăng ký miễn phí tại gitleaks.io |

Caller workflow dùng `secrets: inherit` nên tên secret phải đúng như bảng (không phân
biệt hoa thường). Với organization, có thể đặt các secret này ở mức org và chia cho
nhiều repo.

## 6. Cấu hình Settings của repo

1. **Settings → Actions → General**
   - *Actions permissions*: cho phép actions và reusable workflows (mặc định *Allow all
     actions* là được; nếu giới hạn, thêm `kokoroou/agent-toolkit/*`, `anthropics/*`,
     `actions/*`, `googleapis/release-please-action@*`).
   - *Workflow permissions*: **Read and write permissions** và tick **Allow GitHub
     Actions to create and approve pull requests**. Thiếu bước này agent không mở được
     PR và release-please không mở được release PR.
2. **Settings → General → Pull Requests**: bật *Allow squash merging* (merge gate dùng
   squash) và nên bật *Automatically delete head branches*.
3. **Settings → Advanced Security** (trên sidebar; trước đây tên là *Code
   security*): bật *Dependabot alerts* và *Dependabot security updates* (miễn phí cả với
   repo private, không cần mua gói GitHub Advanced Security dù trang mang tên đó).

Không cần (và gói Free + private cũng không có) branch protection: merge gate tự kiểm
tra checks và statuses.

## 7. Chọn default branch

`workflow_run` (merge gate), `schedule` (triage quét định kỳ, usage report) và
`workflow_dispatch` chỉ chạy **file workflow nằm trên default branch**. Chọn một:

| Cách | Làm gì | Ưu / nhược |
|---|---|---|
| **A. `develop` là default** (khuyến nghị) | *Settings → General → Default branch* → `develop` | Caller workflow sống ở đó; `Closes #N` tự đóng issue; `main` chỉ nhận merge tay khi release. PR thường của người khác cũng mặc định vào `develop` |
| **B. Giữ `main` là default** | Commit caller vào `main`, và mỗi lần sửa workflow phải merge sang `main` | Không đổi thói quen, nhưng dễ quên đồng bộ — workflow trên `develop` khác `main` sẽ gây hành vi khó hiểu |

## 8. Commit và kiểm tra

```bash
git switch <default-branch>
git add .github CLAUDE.md
git commit -m "ci: add agent-toolkit pipeline"
git push
git switch develop && git merge --ff-only <default-branch> && git push   # nếu dùng cách B
```

Kiểm tra theo thứ tự:

1. **Actions** tab: thấy các workflow `CI`, `Agent Triage`, `Agent Implement`,
   `Agent Review`, `Agent Merge Gate`, `Release`, `Agent Usage Report`. Không có file nào
   báo lỗi cú pháp (biểu tượng ⚠).
2. Chạy CI tay: *Actions → CI → Run workflow* trên `develop` → phải xanh. Run này cũng
   ghi baseline coverage cho `develop`.
3. **Issues → New issue → Feature / change request** với một thay đổi nhỏ, rõ ràng, ví dụ:
   - Goal: "Thêm hàm `add(a, b)` trả về tổng hai số."
   - Constraints: "None"
   - Acceptance criteria: "- [ ] `add(2, 3)` trả về 5  - [ ] có unit test"
4. Theo dõi: `Agent Triage` gắn `ready-for-plan` → `Agent Implement` mở PR
   `agent/issue-N` → `CI` + `Agent Review` → `Agent Merge Gate` merge vào `develop` và
   đóng issue. Thường mất 10–30 phút.

Nếu kẹt ở bước nào, xem [§12](#12-xử-lý-sự-cố).

## 9. Tuỳ chọn

### 9.1 GitHub Projects

1. Tạo Project (v2): *Profile → Projects → New project* (hoặc trong org).
2. Thêm hai field **Single select**: `Priority` với option `P0`, `P1`, `P2`, `P3`;
   `Size` với option `XS`, `S`, `M`, `L`, `XL` (đúng chính tả).
3. Lấy số project từ URL (`.../projects/3` → `3`).
4. Trong `agent-triage.yml`, bỏ comment và điền:
   ```yaml
   project-owner: kokoroou
   project-number: "3"
   ```
5. Thêm secret `PROJECT_TOKEN` ([GETTING-STARTED §6](GETTING-STARTED.md#6-pat-cho-github-projects-tuỳ-chọn)).

### 9.2 Dependabot

Sửa `.github/dependabot.yml`: đổi `package-ecosystem: npm` thành ecosystem của bạn
(`pip`, `gomod`, `cargo`, `maven`, `gradle`, `composer`, `docker`…), thêm khối nếu
dùng nhiều ecosystem. PR của Dependabot không có nhãn `agent` nên merge gate để bạn tự
merge; muốn agent review, gắn nhãn `agent` vào PR đó.

### 9.3 ci-doctor (gh-aw)

Agent quan sát lỗi CI trên `develop`/`main` (thứ vòng fix trên PR không thấy) và tạo
issue `needs-triage`:

```bash
gh extension install github/gh-aw     # nếu chưa có
gh aw add kokoroou/agent-toolkit/ci-doctor
gh aw compile                          # sinh .github/workflows/ci-doctor.lock.yml
gh aw secrets set ANTHROPIC_API_KEY    # hoặc theo hướng dẫn gh aw cho engine claude
git add .github && git commit -m "ci: add ci-doctor" && git push
```

Commit cả file `.md` và `.lock.yml` lên default branch.

### 9.4 Release

`release.yml` chạy release-please khi push lên `main`:

- `release-type`: `node`, `python`, `go`, `rust`, `java`, `simple`… — quyết định file
  version nào được cập nhật.
- Muốn đính kèm file build vào GitHub Release: bỏ comment `setup-command`,
  `build-command`, `artifact-paths`.

Quy trình: merge `develop` → `main` (PR tay) → release-please mở PR "chore(main): release x.y.z"
→ review CHANGELOG → merge → tag + GitHub Release. Commit phải theo Conventional
Commits (`feat:` → minor, `fix:` → patch, `feat!:` → major); CI đã kiểm tiêu đề PR.

## 10. Ghim và nâng cấp phiên bản toolkit

- `--ref v0` ghim vào **tag di động** của major hiện tại: nhận bản vá và tính năng mới,
  không nhận breaking change (trước 1.0.0, breaking change tăng minor nên `v0` vẫn có thể
  đổi hành vi — đọc [CHANGELOG](../CHANGELOG.md) khi cập nhật).
- Ghim chặt hơn: `--ref v0.1.0` hoặc một commit SHA.
- Plugin (agent/lệnh) được cài từ `toolkit-marketplace`, mặc định là nhánh mặc định của
  toolkit. Để ghim cả plugin, thêm vào các job gọi `triage.yml`, `implement.yml`,
  `review.yml` (kể cả job `fix`):

  ```yaml
  with:
    toolkit-marketplace: https://github.com/kokoroou/agent-toolkit.git#v0
  ```

Nâng cấp (ví dụ `v0` → `v1`):

```bash
cd ~/code/my-project
grep -rl 'kokoroou/agent-toolkit/.github/workflows/' .github/workflows \
  | xargs sed -i 's#\(kokoroou/agent-toolkit/\.github/workflows/[a-z-]*\.yml\)@v0#\1@v1#'
git diff    # đọc CHANGELOG của toolkit để biết input nào đổi
```

Muốn lấy template mới (input mới, trigger mới), chạy lại bootstrap vào một thư mục tạm
và so sánh:

```bash
git clone -q https://github.com/kokoroou/agent-toolkit /tmp/agent-toolkit-new
tmp=$(mktemp -d) && git -C "$tmp" init -q
/tmp/agent-toolkit-new/scripts/bootstrap.sh "$tmp" --ref v1 --no-labels
diff -ru "$tmp/.github" .github
```

(`--no-labels` vì thư mục tạm không có remote GitHub. Nhãn mới, nếu có, tạo bằng cách
chạy lại bootstrap vào repo thật mà không `--force`: file đã có được giữ nguyên.)

## 11. Vận hành hằng ngày

| Muốn | Làm |
|---|---|
| Giao việc cho agent | Mở issue bằng template; triage tự quyết |
| Build một issue size L hoặc đã bị `needs-human` | Sửa issue cho rõ, bỏ nhãn `needs-human`, gắn **`agent:implement`** |
| Triage lại issue | Gắn nhãn `needs-triage` hoặc *Actions → Agent Triage → Run workflow* |
| Chặn một PR agent | Gắn `do-not-merge` (hoặc `risk:high`) |
| Cho agent review PR của người | Gắn nhãn `agent` vào PR (PR sẽ đủ điều kiện auto-merge!) |
| Tiếp tục sau `needs-human` trên PR | Tự sửa và push, bỏ nhãn; merge gate chạy lại khi CI xong |
| Xem chi phí | Issue `pipeline-usage`, hoặc Step Summary của từng run |

## 12. Xử lý sự cố

| Triệu chứng | Nguyên nhân thường gặp | Cách xử lý |
|---|---|---|
| Không workflow nào chạy khi mở issue | Caller không nằm trên default branch; Actions bị tắt | §7; *Settings → Actions → General* |
| `Agent Merge Gate` không bao giờ chạy | File không ở default branch; tên CI không phải `CI` | §7; §2.3 |
| Agent không mở được PR: `GitHub Actions is not permitted to create or approve pull requests` | Thiếu quyền ở §6 | Bật *Allow GitHub Actions to create and approve pull requests* |
| Bước *Mint GitHub App token* lỗi | App chưa cài vào repo, sai App ID, private key thiếu dòng BEGIN/END | [GETTING-STARTED §5](GETTING-STARTED.md#5-tạo-github-app-cho-agent-khuyến-nghị-mạnh), đặt lại secret |
| Lỗi xác thực Claude / `401` | Thiếu hoặc sai `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`, OAuth token hết hạn | Tạo lại (`claude setup-token`), đặt lại secret |
| PR agent không có check CI (không dùng App) | Bình thường: CI được dispatch riêng, xem trong Actions tab | Dùng App để check hiện trên PR |
| CI báo `coverage-command must print the percentage on its last line` | Dòng cuối stdout của `coverage-command` không chứa số | Chuyển output khác sang `>&2` (§3.3) |
| Agent thử lệnh bị từ chối (`permission denied` / tool not allowed trong transcript) | Lệnh thiếu trong `extra-allowed-tools` | Thêm vào cả `agent-implement.yml` và job `fix` |
| Issue đã merge vẫn mở | Merge gate không chạy tới bước đóng; PR không có `Closes #N` | Kiểm tra log merge gate; đóng tay |
| PR bị `needs-human` sau 3 lần fix | Circuit breaker | Đọc transcript `transcript-fix-*`, sửa tay hoặc làm rõ issue rồi gắn lại `agent:implement` |
| Triage không phản hồi khi trả lời câu hỏi | Comment từ bot bị bỏ qua; issue không còn `awaiting-clarification` | Comment bằng tài khoản người; gắn lại `needs-triage` |

Vẫn không rõ: mở run bị lỗi → xem Step Summary và tải artifact `transcript-*`.
