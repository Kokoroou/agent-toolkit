# Thêm agent-toolkit vào một dự án

[English](ADD-TO-PROJECT.md) · **Tiếng Việt**

Hướng dẫn cài pipeline agent vào **một repo dự án** (mới hoặc đã có code).

> Lần đầu dùng toolkit? Làm [GETTING-STARTED.md](GETTING-STARTED.vi.md) trước: lấy thông
> tin đăng nhập Claude, tạo GitHub App (một lần cho mọi dự án).

**Lộ trình ngắn nhất (~10 phút + thời gian agent chạy):**

1. Chạy [lệnh cài](#cài-bằng-một-lệnh) trong thư mục clone của repo dự án.
2. Kiểm tra lệnh lint/test/coverage mà script điền theo stack → [§3](#3-sửa-workflow-cho-stack-của-dự-án).
3. Điền `CLAUDE.md` (lệnh, kiến trúc, chỗ không được sửa) → [§4](#4-viết-claudemd).
4. Mở một issue nhỏ và xem nó đi hết vòng → [§8](#8-commit-và-kiểm-tra).

Các mục 1–9 mô tả từng bước mà lệnh cài làm bên trong, để làm tay hoặc tinh chỉnh sau.
Mục 10–12 dùng về sau: nâng cấp, vận hành hằng ngày, xử lý sự cố.

Mục lục:

- [Cài bằng một lệnh](#cài-bằng-một-lệnh)
0. [Checklist](#0-checklist)
1. [Chuẩn bị repo](#1-chuẩn-bị-repo)
2. [Chạy bootstrap](#2-chạy-bootstrap) *(cài tay)*
3. [Sửa workflow cho stack của dự án](#3-sửa-workflow-cho-stack-của-dự-án)
4. [Viết `CLAUDE.md`](#4-viết-claudemd)
5. [Thêm secrets](#5-thêm-secrets) *(cài tay)*
6. [Cấu hình Settings của repo](#6-cấu-hình-settings-của-repo) *(cài tay)*
7. [Chọn default branch](#7-chọn-default-branch)
8. [Commit và kiểm tra](#8-commit-và-kiểm-tra)
9. [Tuỳ chọn: Projects, Dependabot, ci-doctor, release](#9-tuỳ-chọn)
10. [Ghim và nâng cấp phiên bản toolkit](#10-ghim-và-nâng-cấp-phiên-bản-toolkit)
11. [Vận hành hằng ngày](#11-vận-hành-hằng-ngày)
12. [Xử lý sự cố](#12-xử-lý-sự-cố)

---

## Cài bằng một lệnh

Điều kiện: repo đã có trên GitHub, có ít nhất một commit, bạn có quyền admin. Đứng trong
thư mục clone của repo dự án rồi chạy:

```bash
# Linux, macOS, WSL, Git Bash
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh | bash
```

```powershell
# Windows PowerShell
irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1 | iex
```

Script (`scripts/install.sh`; bản Windows cài Git for Windows và GitHub CLI bằng `winget`
nếu thiếu, rồi chạy chính script đó bằng Git Bash) làm lần lượt:

| Bước | Làm gì | Tương ứng mục |
|---|---|---|
| 1 | Kiểm tra `git`, `gh` (đề nghị cài nếu thiếu) và `gh auth login` | GETTING-STARTED §3 |
| 2 | Nhận diện stack (`package.json` + lockfile → node/pnpm/yarn, `pyproject.toml`/`requirements.txt` → python, `go.mod` → go), chép template với lệnh đúng stack, tạo nhãn và branch `develop` | §2, §3 |
| 3 | Đặt secret: token Claude, App ID + private key, `PROJECT_TOKEN` | §5 |
| 4 | Bật *Workflow permissions* (read/write + tạo PR), squash merge, xoá branch sau merge, Dependabot alerts | §6 |
| 5 | Commit `.github/` + `CLAUDE.md`, push lên default branch và `develop`, đặt `develop` làm default branch | §7, §8 |

Chỉ những gì chưa có mới được hỏi: stack (Enter để nhận giá trị nhận diện), cách đăng
nhập Claude và token (nhập ẩn; có thể để script chạy `claude setup-token`), App ID và
đường dẫn file `.pem` (tự đoán file mới nhất trong `~/Downloads`), có commit/đổi default
branch không. Secret đã có trong repo được giữ nguyên trừ khi bạn đồng ý thay.

Chạy script khi đang đứng ở default branch (sau lần chạy đầu thường là `develop`): ở branch
khác, script dừng ngay trước khi ghi file và báo bạn cần chuyển branch, hoặc dùng
`--no-commit` để tự commit. Nếu branch local khác `origin`, script bỏ qua bước commit và
nói bạn cần làm gì. Cuối cùng nó in danh sách việc còn lại — luôn
gồm **điền `CLAUDE.md`** (§4), **kiểm tra lệnh theo stack** (§3) và **thử một issue nhỏ**
(§8). Chạy lại script an toàn: file đã có được giữ, nhãn được cập nhật.

Cần xem trước hoặc sửa script? Clone toolkit rồi chạy `scripts/install.sh` (hoặc
`scripts/install.ps1`) từ bản clone; `--help` in đầy đủ tuỳ chọn.

<details>
<summary><b>Script nhớ câu trả lời thế nào — dự án sau gần như không phải nhập lại</b></summary>

Cuối lần chạy đầu, script đề nghị nhớ câu trả lời:

| Loại | Lưu ở đâu |
|---|---|
| Token (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `PROJECT_TOKEN`) | Kho khoá của hệ điều hành, mục `agent-toolkit`: **macOS Keychain**; **Linux** Secret Service (GNOME Keyring/KWallet, qua `secret-tool` — gói `libsecret-tools`, cần phiên desktop); **Windows** file `~/.config/agent-toolkit/<TÊN>.dpapi` mã hoá bằng DPAPI (chỉ tài khoản Windows của bạn trên máy đó giải mã được). Không có kho khoá (vd máy chủ không desktop, WSL) thì token **không được lưu** và sẽ được hỏi lại. |
| App ID, đường dẫn file `.pem`, `--ref`, project owner | `~/.config/agent-toolkit/install.env` (quyền `600`, dạng `KEY=value`, không có bí mật) |

Từ dự án thứ hai, lệnh ở trên gần như không hỏi gì. Một số lớp bảo vệ khác:

- Token không bao giờ được ghi ra file thường hay truyền trên dòng lệnh (không lộ qua
  `ps`); script đưa chúng vào `gh secret set` và kho khoá qua stdin.
- `install.env` chỉ được đọc như dữ liệu (không `source`), chỉ nhận các khoá đã biết; dòng
  chứa token bị bỏ qua kèm cảnh báo; file mà người dùng khác ghi được thì bị bỏ qua cả file.
- Private key của App không được sao chép — chỉ lưu đường dẫn tới file `.pem` của bạn.
  Nên để file này trong thư mục riêng (`chmod 600`), hoặc xoá sau khi đã cài xong mọi repo.
- Kho khoá chống lộ qua backup, đồng bộ thư mục, commit nhầm hay người dùng khác trên máy,
  nhưng **không** chống được mã độc chạy dưới chính tài khoản của bạn. Muốn chặt hơn: đặt
  `AGENT_TOOLKIT_SECRET_STORE=none` và lấy token từ password manager mỗi lần chạy, ví dụ
  `CLAUDE_CODE_OAUTH_TOKEN=$(op read op://Private/claude/token) bash install.sh`
  (1Password; tương tự `bw get password …`, `pass show …`).
- Xoá token đã lưu: macOS `security delete-generic-password -s agent-toolkit -a <TÊN>`;
  Linux `secret-tool clear service agent-toolkit account <TÊN>`; Windows xoá file `.dpapi`.
- Token Claude chỉ cần để đặt secret cho repo; nếu lộ, thu hồi ở
  [Claude Console](https://platform.claude.com/settings/keys) (API key) hoặc tạo lại bằng
  `claude setup-token`, rồi chạy lại script để cập nhật.

`AGENT_TOOLKIT_CONFIG` trỏ tới file config khác nếu cần.

</details>

<details>
<summary><b>Chạy không hỏi (CI, script của bạn) và bảng tham số</b></summary>

Truyền giá trị bằng tham số hoặc biến môi trường và thêm `--yes`. Giá trị truyền theo
cách này luôn được ghi, kể cả khi secret đã có.

```bash
export CLAUDE_CODE_OAUTH_TOKEN=...          # hoặc ANTHROPIC_API_KEY=...
export AGENT_APP_ID=123456 AGENT_APP_PRIVATE_KEY_FILE=~/keys/my-agent.pem
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh \
  | bash -s -- ~/code/my-project --stack python --yes
```

```powershell
$env:CLAUDE_CODE_OAUTH_TOKEN = '...'
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1))) --stack python --yes
```

| Tham số | Biến môi trường | Ý nghĩa |
|---|---|---|
| `<path>` | | Repo dự án (mặc định: thư mục hiện tại) |
| `--ref <ref>` | `AGENT_TOOLKIT_REF` | Phiên bản toolkit để ghim (mặc định `v0`, xem §10) |
| `--stack <s>` | `AGENT_TOOLKIT_STACK` | `auto` (mặc định), `node`, `pnpm`, `yarn`, `python`, `go`, `none` (giữ lệnh Node mặc định để tự sửa) |
| `--claude-auth <a>` | `AGENT_TOOLKIT_CLAUDE_AUTH` | `oauth`, `api-key` hoặc `skip` |
| | `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` | Giá trị secret Claude |
| `--app-id <id>` | `AGENT_APP_ID` | App ID của GitHub App |
| `--app-key <file>` | `AGENT_APP_PRIVATE_KEY_FILE` (hoặc nội dung: `AGENT_APP_PRIVATE_KEY`) | Private key `.pem` |
| `--project-owner`, `--project-number` | `PROJECT_OWNER`, `PROJECT_NUMBER`, `PROJECT_TOKEN` | GitHub Projects (§9.1) |
| `--default-develop` / `--keep-default` | | Đổi / giữ default branch (mặc định: hỏi, `--yes` → đổi) |
| `--commit` / `--no-commit` | | Commit + push hay để bạn tự làm (mặc định: hỏi, `--yes` → commit) |
| `--skip-secrets`, `--skip-settings`, `--no-labels`, `--force` | | Bỏ qua từng phần; `--force` ghi đè file đã có (không có thì trình cài liệt kê và hỏi — mặc định: giữ nguyên) |
| `-y`, `--yes` | | Không hỏi gì; secret thiếu thì bỏ qua và báo ở cuối |

</details>

## 0. Checklist

Mục đánh dấu ⚙ được lệnh cài làm tự động; cài tay thì làm theo mục tương ứng.

- [ ] Repo có ít nhất một commit, lint/test chạy được trên máy (§1)
- [ ] ⚙ File + nhãn + branch `develop` đã có (§2)
- [ ] Các khối `edit for your stack` khớp dự án trong `ci.yml`, `agent-implement.yml`, `agent-merge-gate.yml` (§3)
- [ ] `CLAUDE.md` đã điền (§4)
- [ ] ⚙ Secret Claude (+ App) đã thêm (§5)
- [ ] ⚙ Workflow permissions: *Read and write* + *Allow GitHub Actions to create and approve pull requests* (§6)
- [ ] ⚙ Caller workflow nằm trên **default branch** (§7)
- [ ] Thử một issue nhỏ đi hết vòng (§8)

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

> Đã dùng [lệnh cài](#cài-bằng-một-lệnh)? Bỏ qua mục này — trừ §2.3 nếu repo có sẵn
> `ci.yml`, `CLAUDE.md` hay issue template.

### 2.1 Lệnh

```bash
git clone https://github.com/kokoroou/agent-toolkit /tmp/agent-toolkit
cd ~/code/my-project && gh auth status          # gh phải đăng nhập, có quyền admin repo
/tmp/agent-toolkit/scripts/bootstrap.sh ~/code/my-project --ref v0
```

`bootstrap.sh` chỉ lo phần file + nhãn + `develop`; [`install.sh`](#cài-bằng-một-lệnh)
gọi nó rồi làm tiếp secret, settings và commit.

| Tuỳ chọn | Ý nghĩa |
|---|---|
| `--stack <s>` | Điền sẵn lệnh cho stack: `auto` (mặc định, nhận diện từ file trong repo), `node`, `pnpm`, `yarn`, `python`, `go`, `none`. Các giá trị giống ví dụ ở §3.3. |
| `--ref <ref>` | Ghim mọi `uses: kokoroou/agent-toolkit/...@<ref>`. Khuyến nghị `v0` (tag di động của bản 0.x hiện tại; `v1` khi toolkit lên 1.0.0). `main` = luôn mới nhất, chỉ dùng cho sandbox. Mặc định: `main`. |
| `--force` | Ghi đè file đã có trong repo dự án. |
| `--no-labels` | Không tạo nhãn / branch `develop` (khi chưa có `gh` hoặc đã tạo rồi). |

### 2.2 Bootstrap làm gì

1. Chép từ `templates/` sang repo dự án:

   | File | Vai trò |
   |---|---|
   | `.github/workflows/ci.yml` | CI (tên `CI`): lint, format, test, coverage, tiêu đề PR, Semgrep, Gitleaks |
   | `.github/workflows/agent-triage.yml` | Triage issue khi mở/sửa/comment, quét 6 giờ/lần |
   | `.github/workflows/agent-implement.yml` | Build agent tuỳ chọn trên GitHub Actions; chạy khi gắn nhãn `agent:implement`, hoặc sau triage khi biến repo `AGENT_AUTO_BUILD` là `true`. Mặc định bạn thi công trong Claude Code bằng `/pipeline:build N` |
   | `.github/workflows/agent-review.yml` | Review PR mang nhãn `agent` (tên `Agent Review`) |
   | `.github/workflows/agent-merge-gate.yml` | Chạy sau `CI`/`Agent Review`: merge, yêu cầu sửa (`/pipeline:build pr P`, hoặc build agent trên Actions khi `AGENT_AUTO_BUILD=true`), hoặc chặn |
   | `.github/workflows/release.yml` | release-please khi push `main` |
   | `.github/workflows/agent-usage-report.yml` | Báo cáo phút Actions + chi phí Claude hằng tuần |
   | `.github/ISSUE_TEMPLATE/{feature,bug,config}.yml` | Template issue có cấu trúc, tắt issue trống |
   | `.github/pull_request_template.md` | Template PR |
   | `.github/dependabot.yml` | Cập nhật dependency, PR vào `develop` |
   | `CLAUDE.md` | Khung hướng dẫn dự án cho agent |

2. Thay `@main` trong các dòng `uses:` bằng `--ref`, điền lệnh theo `--stack` vào các
   khối `edit for your stack`, `dependabot.yml`, `release.yml` và mục *Commands* của `CLAUDE.md`.
3. Tạo ~24 nhãn (`needs-triage`, `agent`, `risk:high`, `size:M`…) — chạy lại an toàn.
4. Tạo branch `develop` từ default branch nếu chưa có.
5. Ghi `.github/agent-toolkit.lock` (bản toolkit, stack, danh sách file nó quản lý) để
   `upgrade.sh` nâng cấp được về sau (§10).

### 2.3 Repo đã có sẵn file

Bootstrap in danh sách `Kept existing`. Các file này thuộc về dự án: bootstrap và
`upgrade.sh` không bao giờ ghi đè chúng (§10.4). Với từng file:

- **`ci.yml` riêng**: có thể giữ CI cũ, nhưng workflow phải tên **`CI`** (merge gate và
  vòng fix tìm theo tên này), có `workflow_dispatch:` và chạy trên `pull_request` vào
  `develop`. Hoặc đổi `ci-workflow` / `workflows: [...]` trong caller cho khớp tên CI cũ.
- **`CLAUDE.md` có sẵn**: thêm các mục *Commands*, *Architecture*, *Do not touch* từ
  `/tmp/agent-toolkit/templates/CLAUDE.md`.
- **Issue template riêng**: giữ được, nhưng template phải gắn nhãn `needs-triage` và nên
  có các mục Goal / Constraints / Acceptance criteria để triage chấm điểm tốt.

## 3. Sửa workflow cho stack của dự án

Template mặc định cho **Node + Jest + Prettier + ESLint**; `--stack` của bootstrap/install
đã điền sẵn lệnh cho pnpm, yarn, Python (pytest + ruff) và Go. Vẫn nên kiểm tra các khối
`# ── edit for your stack ──` và sửa cho khớp dự án (ví dụ dự án Python không dùng ruff).

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

Hai chỗ này chỉ chạy khi build trên GitHub Actions (nhãn `agent:implement`, hoặc
`AGENT_AUTO_BUILD=true`, xem §3.4). Build do bạn khởi động bằng `/pipeline:build` dùng
phiên Claude Code của bạn và các lệnh trong `CLAUDE.md`.

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

- **Build chạy ở đâu.** Mặc định không có gì tự build: triage comment `/pipeline:build N`
  lên issue đã sẵn sàng, merge gate comment `/pipeline:build pr P` lên PR agent bị đỏ, và
  bạn chạy các lệnh đó trong Claude Code (trên máy hoặc trên web). Muốn tự build trên
  GitHub Actions thì đặt biến repo `AGENT_AUTO_BUILD=true` (*Settings → Secrets and
  variables → Actions → Variables*, hoặc `gh variable set AGENT_AUTO_BUILD --body true`):
  triage sẽ dispatch `agent-implement.yml` và merge gate chạy job `fix`. Không cần sửa file.
- `agent-triage.yml`: `max-rounds` (số vòng hỏi lại, 1–5, mặc định 5), `auto-implement-max-size`
  (`XS|S|M|L`, khi `AGENT_AUTO_BUILD=true`; lớn hơn thì chờ bạn).
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

> Lệnh cài đã đặt secret cho bạn. Mục này dành cho cài tay, đổi token, hoặc thêm
> `PROJECT_TOKEN` / `GITLEAKS_LICENSE` về sau.

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
| `ANTHROPIC_API_KEY` *hoặc* `CLAUDE_CODE_OAUTH_TOKEN` | ✔ | Xem [GETTING-STARTED §4](GETTING-STARTED.vi.md#4-chuẩn-bị-thông-tin-đăng-nhập-claude) |
| `AGENT_APP_ID`, `AGENT_APP_PRIVATE_KEY` | khuyến nghị | App phải **được cài vào repo này** ([GETTING-STARTED §5.3](GETTING-STARTED.vi.md#53-cài-app-vào-repo)) |
| `PROJECT_TOKEN` | nếu dùng Projects | classic PAT, scope `project` + `repo` |
| `GITLEAKS_LICENSE` | chỉ repo thuộc organization | đăng ký miễn phí tại gitleaks.io |

Caller workflow truyền từng secret theo tên (`${{ secrets.ANTHROPIC_API_KEY }}`…) nên
tên secret phải đúng như bảng (không phân biệt hoa thường). Với organization, có thể đặt các secret này ở mức org và chia cho
nhiều repo.

## 6. Cấu hình Settings của repo

> Lệnh cài đã bật các mục 1–3 dưới đây (trừ khi dùng `--skip-settings`). Đọc để kiểm tra
> khi gặp lỗi quyền.

1. **Settings → Actions → General**
   - *Actions permissions*: cho phép actions và reusable workflows (mặc định *Allow all
     actions* là được; nếu giới hạn, thêm `kokoroou/agent-toolkit/*`, `anthropics/*`,
     `actions/*`, `googleapis/release-please-action@*`, `gitleaks/gitleaks-action@*`,
     `oven-sh/setup-bun@*` — cái cuối do `anthropics/claude-code-action` gọi).
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
5. Thêm secret `PROJECT_TOKEN` ([GETTING-STARTED §6](GETTING-STARTED.vi.md#6-pat-cho-github-projects-tuỳ-chọn)).

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

### 10.1 Có hai thứ cần nâng cấp

| Thứ | Nằm ở đâu | Nâng cấp thế nào |
|---|---|---|
| Logic pipeline (reusable workflow, plugin) | Trong toolkit, dự án gọi bằng `uses: …@v0` | **Tự động** ở run kế tiếp khi toolkit phát hành trong cùng major (`v0`). Sang major mới: `upgrade.sh --to v1` |
| File đã chép vào dự án (caller workflow, issue/PR template, `dependabot.yml`) | Trong repo dự án | `upgrade.sh` — khi CHANGELOG nói template có input/trigger/nhãn mới |

### 10.2 Lệnh nâng cấp

Trong thư mục clone của dự án, đứng ở default branch, không có thay đổi chưa commit
trong `.github/`:

```bash
# xem trước, không ghi gì
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/upgrade.sh | bash -s -- --dry-run
# áp dụng: bản mới nhất của major đang ghim (v0), hoặc --to v1 / --to v0.3.0
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/upgrade.sh | bash -s -- --to v1
git diff && git add .github && git commit -m "ci: upgrade agent-toolkit to v1"
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1))) upgrade --to v1
```

Script không commit; nó in bảng từng file, CHANGELOG từ bản đang cài tới bản mới và cập
nhật nhãn (`--no-labels` để bỏ). Thoát mã `1` nếu còn xung đột.

### 10.3 Cách script giữ lại chỉnh sửa của bạn

`bootstrap.sh` (và `install.sh`) ghi **`.github/agent-toolkit.lock`** — hãy commit file
này, và đừng sửa tay ngoài các dòng `managed=` (§10.4):

```
version=0.1.0              # bản toolkit đã sinh ra các file
ref=v0                     # --ref đã ghim
commit=45c2ae5…            # commit chính xác của toolkit
stack=python               # --stack đã dùng
managed=.github/workflows/ci.yml   # file do toolkit quản lý (một dòng mỗi file)
```

Khi nâng cấp, script sinh lại file của **bản cũ** (commit + stack trong lock) và của
**bản mới**, rồi với từng file *managed* so ba phía — như `git merge`:

| Bản của bạn so với bản cũ | Toolkit đổi file? | Kết quả |
|---|---|---|
| Chưa sửa | có | `↑` thay bằng bản mới |
| Đã sửa (vd khối `edit for your stack`) | không | `=` giữ nguyên |
| Đã sửa | có, ở chỗ khác | `~` bản mới + chỉnh sửa của bạn (`git merge-file`) |
| Đã sửa | có, **cùng dòng** | `!` xung đột: file chứa `<<<<<<< yours` … `>>>>>>> agent-toolkit v1`, sửa tay |
| Không có (file mới của toolkit) | — | `+` thêm, ghi vào `managed=` |
| Bạn đã xoá | — | không thêm lại |
| Toolkit bỏ file | — | xoá nếu bạn chưa sửa, ngược lại giữ và báo `!` |

Để nâng cấp không xung đột: chỉ sửa giá trị trong các khối `edit for your stack` và các
input của `with:`; muốn thêm bước riêng thì viết workflow riêng thay vì sửa caller.

### 10.4 File trùng tên — ai sở hữu file nào

| Loại | File | Khi nâng cấp |
|---|---|---|
| **Toolkit quản lý** | file bootstrap đã chép (dòng `managed=` trong lock) | 3-way merge như trên |
| **Của dự án** | file đã có **trước** khi cài (bootstrap báo `Kept existing`), vd `ci.yml` hay issue template riêng | không bao giờ bị ghi; nếu template tương ứng đổi, script báo `·` để bạn tự gộp |
| **Chỉ sinh lần đầu** | `CLAUDE.md` | không bao giờ bị ghi; script đưa link so sánh nếu template đổi |

Muốn chuyển một file của dự án sang cho toolkit quản lý: xoá file, chạy lại
`bootstrap.sh --ref <ref đang dùng>` (không `--force`), gộp lại phần riêng rồi commit.
Muốn toolkit thôi quản lý một file: xoá dòng `managed=` của nó trong lock.

### 10.5 Dự án cài trước khi có lock

Script tự dò: đọc `@ref` trong `uses:`, sinh file của từng bản phát hành gần đây và chọn
bản khớp với repo nhiều nhất (in `guessed: N identical files`). Chỉ caller có `uses:
kokoroou/agent-toolkit/…` và file còn y nguyên được coi là toolkit quản lý. Chắc chắn hơn:
chỉ rõ `--from v0.1.0` (và `--stack` nếu đã chọn stack khác bản nhận diện). File không xác
định được bản gốc được giữ nguyên, bản mới đặt cạnh ở `<file>.upstream` để so sánh — gộp
tay rồi xoá file `.upstream`. Sau lần nâng cấp đầu, lock được tạo và các lần sau không
cần dò nữa.

## 11. Vận hành hằng ngày

| Muốn | Làm |
|---|---|
| Giao việc cho agent | Mở issue bằng template; triage tự quyết |
| Thi công một issue đã sẵn sàng | Trong Claude Code trên dự án (máy bạn hoặc web): `/pipeline:build N`, hoặc "thi công issue N". Xác nhận push khi được hỏi |
| Làm dần backlog | `/pipeline:build` không tham số: xếp hạng issue sẵn sàng và PR agent bị đỏ, đề xuất thứ tự, thi công lần lượt những việc bạn duyệt |
| Sửa PR agent bị đỏ | `/pipeline:build pr P` (merge gate comment sẵn lệnh này trên PR) |
| Build một issue size L hoặc đã bị `needs-human` | Sửa issue cho rõ, bỏ nhãn `needs-human`, rồi `/pipeline:build N` (hoặc gắn **`agent:implement`** để build trên Actions) |
| Triage lại issue | Gắn nhãn `needs-triage` hoặc *Actions → Agent Triage → Run workflow* |
| Đổi yêu cầu | Sửa nội dung issue (nguồn sự thật là issue, không phải comment). Issue đang `needs-triage` / `awaiting-clarification` / `ready-for-plan` được triage lại tự động, vòng hỏi đếm lại từ 0 nếu triage trước đã kết luận. PR agent đang mở cho issue bị gắn `needs-human` → đóng PR, xoá branch, build lại (`/pipeline:build N` hoặc `agent:implement`) khi issue `ready-for-plan` trở lại |
| Huỷ, không làm tiếp | Đóng issue. Triage và build bỏ qua; build đang chạy không push, không mở PR; PR đã mở không được fix, merge gate gắn `needs-human` thay vì merge. Đóng luôn PR nếu có |
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
| Bước *Mint GitHub App token* lỗi | App chưa cài vào repo, sai App ID, private key thiếu dòng BEGIN/END | [GETTING-STARTED §5](GETTING-STARTED.vi.md#5-tạo-github-app-cho-agent-khuyến-nghị-mạnh), đặt lại secret |
| Lỗi xác thực Claude / `401` | Thiếu hoặc sai `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`, OAuth token hết hạn | Tạo lại (`claude setup-token`), đặt lại secret |
| PR agent không có check CI (không dùng App) | Bình thường: CI được dispatch riêng, xem trong Actions tab | Dùng App để check hiện trên PR |
| CI báo `coverage-command must print the percentage on its last line` | Dòng cuối stdout của `coverage-command` không chứa số | Chuyển output khác sang `>&2` (§3.3) |
| Agent thử lệnh bị từ chối (`permission denied` / tool not allowed trong transcript) | Lệnh thiếu trong `extra-allowed-tools` | Thêm vào cả `agent-implement.yml` và job `fix` (chỉ build trên Actions) |
| Issue đã merge vẫn mở | Merge gate không chạy tới bước đóng; PR không có `Closes #N` | Kiểm tra log merge gate; đóng tay |
| PR bị `needs-human` sau 3 lần fix | Circuit breaker | Đọc transcript `transcript-fix-*`, sửa tay, chạy `/pipeline:build pr P`, hoặc làm rõ issue rồi build lại |
| Triage không phản hồi khi trả lời câu hỏi | Comment từ bot bị bỏ qua; issue không còn `awaiting-clarification` | Comment bằng tài khoản người; gắn lại `needs-triage` |

Vẫn không rõ: mở run bị lỗi → xem Step Summary và tải artifact `transcript-*`.
