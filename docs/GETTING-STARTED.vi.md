# Bắt đầu với agent-toolkit (người dùng lần đầu)

[English](GETTING-STARTED.md) · **Tiếng Việt**

Tài liệu này dành cho **người dùng GitHub lần đầu dùng agent-toolkit**: bạn muốn cho
Claude Code tự triage issue, viết code, mở PR, review và merge trong các repo của mình.
Bạn **không** cần fork hay sửa toolkit — chỉ cần chuẩn bị tài khoản một lần, sau đó
thêm pipeline vào từng dự án theo [ADD-TO-PROJECT.md](ADD-TO-PROJECT.vi.md).

> Bạn đang bảo trì chính repo `kokoroou/agent-toolkit`? Xem [MAINTAINING.md](MAINTAINING.vi.md).

**Tóm tắt — việc cần làm một lần (~15 phút):**

| # | Việc | Bắt buộc? | Mục |
|---|---|---|---|
| 1 | Cài `gh`, đăng nhập `gh auth login` | ✔ (script cài tự đề nghị) | [§3](#3-cài-công-cụ-trên-máy) |
| 2 | Lấy token Claude: `claude setup-token` (gói Pro/Max) **hoặc** API key | ✔ | [§4](#4-chuẩn-bị-thông-tin-đăng-nhập-claude) |
| 3 | Tạo GitHub App, lấy App ID + file `.pem`, cài App vào repo | khuyến nghị mạnh | [§5](#5-tạo-github-app-cho-agent-khuyến-nghị-mạnh) |
| 4 | Classic PAT cho GitHub Projects | tuỳ chọn | [§6](#6-pat-cho-github-projects-tuỳ-chọn) |
| 5 | Thử trên một repo sandbox trước dự án thật | nên làm | [§8](#8-chạy-thử-trên-repo-sandbox) |

Xong thì sang [ADD-TO-PROJECT.md](ADD-TO-PROJECT.vi.md) — thường chỉ là một lệnh. Thuật ngữ
(triage, merge gate, `needs-human`…): [README](../README.vi.md#thuật-ngữ).

Mục lục:

1. [Pipeline làm gì](#1-pipeline-làm-gì)
2. [Yêu cầu](#2-yêu-cầu)
3. [Cài công cụ trên máy](#3-cài-công-cụ-trên-máy)
4. [Chuẩn bị thông tin đăng nhập Claude](#4-chuẩn-bị-thông-tin-đăng-nhập-claude)
5. [Tạo GitHub App cho agent](#5-tạo-github-app-cho-agent-khuyến-nghị-mạnh)
6. [PAT cho GitHub Projects](#6-pat-cho-github-projects-tuỳ-chọn)
7. [Dùng plugin khi làm việc tay](#7-dùng-plugin-khi-làm-việc-tay-tuỳ-chọn)
8. [Chạy thử trên repo sandbox](#8-chạy-thử-trên-repo-sandbox)
9. [Chi phí và giới hạn](#9-chi-phí-và-giới-hạn)

---

## 1. Pipeline làm gì

```
issue ─▶ triage ─▶ (bạn: /pipeline:build) ─▶ planner ─▶ implementer ─▶ PR ─▶ CI + reviewer ─▶ merge gate ─▶ main ─▶ (bạn) ─▶ release
```

- Bạn mở issue theo template (Goal / Constraints / Acceptance criteria).
- **Triage** đọc issue, hỏi lại tối đa 5 vòng nếu thiếu thông tin hoặc chưa rõ ý định, rồi gắn nhãn
  `type:*`, `priority:*`, `risk:*`, `size:*`.
- Issue đủ ý được gắn `ready-for-plan` kèm comment hướng dẫn bước tiếp. Bạn khởi động
  **build agent** khi muốn: `/pipeline:build N` trong Claude Code trên máy hoặc trên web.
  Nó tạo branch `agent/issue-N`, lập kế hoạch, viết code + test và, sau khi bạn xác nhận,
  mở PR vào `main`. (Tuỳ chọn: đặt biến repo `AGENT_AUTO_BUILD=true` để issue có `risk`
  khác `high` và `size` ≤ M tự build trên GitHub Actions, hoặc gắn nhãn `agent:implement`
  cho từng issue.)
- **CI** (lint, format, test, coverage không giảm, Semgrep, Gitleaks) và **reviewer
  agent** chạy trên PR.
- **Merge gate** squash-merge PR xanh vào `main`; PR đỏ được comment lệnh
  `/pipeline:build pr P` để bạn chạy (với `AGENT_AUTO_BUILD=true` thì PR được gửi lại build
  agent trên Actions, tối đa 3 lần, sau đó dừng với `needs-human`).
- release-please luôn giữ một PR release trên `main`; merge nó sẽ tạo version, CHANGELOG
  và GitHub Release. (Đó là **github-flow** mặc định. Đội muốn test trên `develop` trước
  khi lên `main` thì chọn **gitlab-flow**: PR vào `develop`, *Branch Sync* luôn giữ PR
  promotion `develop` → `main` và merge ngược `main` về sau mỗi lần phát hành —
  [ADD-TO-PROJECT §7.1](ADD-TO-PROJECT.vi.md#71-mô-hình-nhánh-gitlab-flow-hay-github-flow).)

Repo dự án chỉ giữ vài file YAML mỏng gọi vào toolkit (`uses: kokoroou/agent-toolkit/...@v0`),
nên toàn bộ logic được cập nhật từ một nơi. Chi tiết thiết kế: [ARCHITECTURE.md](ARCHITECTURE.vi.md).

## 2. Yêu cầu

| Thứ cần có | Ghi chú |
|---|---|
| Tài khoản GitHub (gói Free là đủ) | Repo dự án có thể private. Toolkit tự thay branch protection bằng merge gate. |
| Quyền **admin** trên repo dự án | Để thêm secret, sửa Settings → Actions, tạo nhãn và branch. |
| Tài khoản Anthropic | API key (trả theo token) **hoặc** gói Claude Pro/Max (dùng OAuth token). |
| Phút GitHub Actions | Repo private trên gói Free có 2 000 phút/tháng; mỗi issue tốn khoảng vài chục phút (xem [§9](#9-chi-phí-và-giới-hạn)). |
| Máy có `git` và GitHub CLI `gh` | Linux, macOS, WSL hoặc Windows. Lệnh cài một bước ([ADD-TO-PROJECT](ADD-TO-PROJECT.vi.md#cài-bằng-một-lệnh)) tự đề nghị cài nếu thiếu. |

## 3. Cài công cụ trên máy

Lệnh cài một bước ([ADD-TO-PROJECT](ADD-TO-PROJECT.vi.md#cài-bằng-một-lệnh)) tự kiểm tra
và đề nghị cài `git`, `gh` rồi chạy `gh auth login`; phần dưới là cách làm tay.

```bash
# GitHub CLI — dùng để tạo nhãn, branch develop, secret và settings
# macOS: brew install gh      Ubuntu/Debian: sudo apt install gh      Windows: winget install GitHub.cli
gh auth login            # chọn GitHub.com → HTTPS → đăng nhập bằng trình duyệt
gh auth status           # kiểm tra: phải thấy "Logged in to github.com" và scope "repo"

# Claude Code CLI — cần cho OAuth token (§4) và để dùng plugin khi làm tay (§7)
npm install -g @anthropic-ai/claude-code
claude --version
```

Tuỳ chọn, chỉ khi muốn thêm agent quan sát CI (ci-doctor):

```bash
gh extension install github/gh-aw
```

## 4. Chuẩn bị thông tin đăng nhập Claude

Các workflow agent cần **một trong hai** secret sau (bạn sẽ thêm vào từng repo dự án ở
bước sau, giờ chỉ cần lấy giá trị):

| Secret | Lấy ở đâu | Khi nào chọn |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Chạy `claude setup-token` trên máy, đăng nhập bằng tài khoản Claude Pro/Max, copy token in ra | Bạn có gói Claude: dùng hạn mức gói, không tính tiền API. |
| `ANTHROPIC_API_KEY` | [Claude Console → API keys](https://platform.claude.com/settings/keys) → *Create Key* (Console đã chuyển từ `console.anthropic.com` sang `platform.claude.com`; link cũ vẫn tự chuyển hướng) | Không có gói Claude, hoặc cần chi phí tách bạch theo API. Nên đặt *spend limit* trong Console. |

Lưu giá trị ở nơi an toàn (password manager). Không commit vào repo.

## 5. Tạo GitHub App cho agent (khuyến nghị mạnh)

**Nói ngắn:** có App thì PR của agent hiện check CI và mọi thứ chạy như người thật push.
Làm một lần, dùng cho mọi repo: [mở link tạo sẵn](#51-tạo-app) → đặt tên → *Create* →
ghi App ID + tải private key → *Install* vào repo.

**Vì sao cần:** GitHub không cho sự kiện tạo bằng `GITHUB_TOKEN` (push, mở PR, gắn nhãn,
merge) kích hoạt workflow khác. Không có App, toolkit vẫn chạy nhờ đường vòng
`workflow_dispatch`, nhưng:

- check CI không hiện trực tiếp trên PR như PR thường;
- CI/smoke sau merge phải được dispatch thủ công bởi toolkit;
- release PR không tự chạy CI.

Có App thì mọi thứ chạy như khi một người thật push. Một App dùng chung được cho mọi
repo của bạn.

### 5.1 Tạo App

1. Mở [trang tạo App điền sẵn cấu hình](https://github.com/settings/apps/new?url=https://github.com/kokoroou/agent-toolkit&public=false&webhook_active=false&contents=write&pull_requests=write&issues=write&actions=write&workflows=write).
   Link này đã điền Homepage URL, bỏ tick Webhook, chọn sẵn các quyền ở bước 3 và
   *Only on this account*; bạn chỉ cần đặt tên rồi kiểm tra lại các bước dưới. Nếu tự vào:
   **ảnh đại diện → Settings → Developer settings → GitHub Apps → New GitHub App**.
   Với organization, dùng `https://github.com/organizations/<ORG>/settings/apps/new` kèm
   cùng phần query phía sau dấu `?`.
2. Điền:
   - **GitHub App name**: tên duy nhất, ví dụ `kokoroou-agent`. Tên này sẽ hiện là tác
     giả của commit/PR (`kokoroou-agent[bot]`).
   - **Homepage URL**: URL bất kỳ, ví dụ `https://github.com/kokoroou/agent-toolkit`.
   - **Webhook**: bỏ tick *Active* (toolkit không dùng webhook).
3. **Repository permissions** (các quyền khác để *No access*):

   | Quyền | Mức | Dùng để |
   |---|---|---|
   | Contents | Read and write | push branch `agent/issue-N`, merge |
   | Pull requests | Read and write | mở PR, sửa nhãn, merge |
   | Issues | Read and write | comment, gắn nhãn, đóng issue |
   | Actions | Read and write | dispatch workflow, đọc log CI cho vòng fix |
   | Workflows | Read and write | chỉ cần nếu agent có thể sửa file trong `.github/workflows/` |
   | Metadata | Read-only | bắt buộc (tự chọn) |

4. **Where can this GitHub App be installed?** → *Only on this account*.
5. Bấm **Create GitHub App**.

### 5.2 Lấy App ID và private key

1. Ở trang App vừa tạo, ghi lại **App ID** (một số, ở mục *About*). Đây là giá trị của
   secret `AGENT_APP_ID`.
2. Cuộn xuống **Private keys → Generate a private key**. Trình duyệt tải về file `.pem`.
   **Toàn bộ nội dung file** (kể cả dòng `-----BEGIN ... KEY-----` và `-----END ... KEY-----`)
   là giá trị của secret `AGENT_APP_PRIVATE_KEY`.

   ```bash
   cat ~/Downloads/kokoroou-agent.*.private-key.pem   # copy toàn bộ output
   ```

3. Cất file `.pem` ở nơi an toàn hoặc xoá sau khi đã thêm secret; nếu lộ, vào lại trang
   App để xoá key và tạo key mới.

### 5.3 Cài App vào repo

1. Trang App → **Install App** → chọn tài khoản của bạn → **Install**.
2. Chọn *Only select repositories* và tick các repo dự án sẽ dùng pipeline (có thể thêm
   repo sau ở [Installed GitHub Apps](https://github.com/settings/installations) → *Configure*).

> Token của App được tạo trong từng run và chỉ có hiệu lực với repo đang chạy, nên App
> **phải được cài vào mọi repo dự án** có secret `AGENT_APP_ID`. Nếu thiếu, bước
> *Mint GitHub App token* sẽ lỗi.

## 6. PAT cho GitHub Projects (tuỳ chọn)

Chỉ cần nếu muốn triage tự thêm issue vào một GitHub Project (v2) và điền `Priority`,
`Size`. Project thuộc **tài khoản cá nhân** không nhận `GITHUB_TOKEN` hay token của App,
nên cần **classic** PAT:

1. Mở [trang tạo classic PAT điền sẵn](https://github.com/settings/tokens/new?scopes=repo,project&description=agent-toolkit%20projects)
   (đã điền Note và tick sẵn scope), hoặc vào
   **Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → Generate new token (classic)**.
2. Kiểm tra lại: Note `agent-toolkit projects`; Expiration tuỳ bạn (nhớ gia hạn); scopes **`repo`** và **`project`**.
3. **Generate token** → copy token → sẽ dùng làm secret `PROJECT_TOKEN`.

> **Đừng dùng fine-grained token.** Nếu trang bạn đang mở có các mục *Repository access*
> và *Permissions → Add permissions* thì đó là trang fine-grained. Loại token này chưa có
> quyền ghi vào Project của tài khoản cá nhân, nên triage sẽ không thêm được issue vào
> Project. Trang classic chỉ có một danh sách checkbox scope (`repo`, `workflow`,
> `project`, ...).

## 7. Dùng plugin khi làm việc tay (tuỳ chọn)

Các sub-agent và lệnh mà pipeline dùng cũng dùng được trong Claude Code trên máy bạn:

```bash
claude plugin marketplace add kokoroou/agent-toolkit
claude plugin install pipeline@agent-toolkit
```

Lệnh này chỉ cài plugin trên máy bạn. Dự án được thiết lập bằng lệnh cài cũng bật plugin
trong `.claude/settings.json` (`extraKnownMarketplaces` + `enabledPlugins`), nên Claude
Code đề nghị cài khi bạn mở dự án, và phiên cloud trên claude.ai/code tự nạp nó
([AGENT-SESSION §5](AGENT-SESSION.vi.md#5-phiên-trên-claude-cloud)).

Trong Claude Code, đứng ở thư mục repo dự án (cần `gh auth login` để lệnh đọc được issue/PR):

| Lệnh | Làm gì |
|---|---|
| `/pipeline:build 42` | **Thi công issue #42 từ đầu đến cuối**: branch, kế hoạch, code, kiểm tra, rồi (sau khi bạn xác nhận) push + PR có `Closes #42` và nhãn `agent`. Hoặc chỉ cần nói "thi công issue 42" |
| `/pipeline:build` | Không tham số: gom issue đã sẵn sàng và PR agent bị đỏ, loại việc đang bị chặn, xếp hạng (PR đỏ trước, rồi priority P0→P3, bug, size nhỏ, cũ hơn), đề xuất thứ tự và thi công lần lượt những việc bạn duyệt. Hoặc hỏi "nên làm gì tiếp?" |
| `/pipeline:build pr 57` | Sửa PR agent #57 theo log CI đỏ / review, rồi push |
| `/pipeline:triage-issue 42` | Chấm điểm, phân loại issue #42, đề xuất câu hỏi làm rõ |
| `/pipeline:plan-feature 42` | Lập kế hoạch theo file cho issue #42, không sửa code |
| `/pipeline:implement-issue 42` | Planner → implementer trên branch hiện tại, commit (không push; workflow Actions dùng) |
| `/pipeline:fix-pr 57 <file-log>` | Sửa PR #57 theo log CI / review, commit (không push; workflow Actions dùng) |
| `/pipeline:review-pr 57` | Review PR #57, trả về verdict |

Cập nhật plugin: `claude plugin marketplace update agent-toolkit`.

Chạy các lệnh này trong sandbox, với `.env` mã hoá và storage cho file không commit:
[AGENT-SESSION.md](AGENT-SESSION.vi.md).

## 8. Chạy thử trên repo sandbox

Trước khi dùng cho dự án thật, nên thử toàn bộ vòng trên một repo nhỏ bỏ đi được.

### 8.1 Tạo sandbox

```bash
gh repo create agent-sandbox --private --clone && cd agent-sandbox
npm init -y
npm install --save-dev jest prettier eslint
mkdir -p src test
cat > src/slugify.js <<'EOF'
module.exports = (s) => s.toLowerCase().trim().replace(/\s+/g, "-");
EOF
cat > test/slugify.test.js <<'EOF'
const slugify = require("../src/slugify");
test("spaces become dashes", () => expect(slugify("Hello World")).toBe("hello-world"));
EOF
cat > eslint.config.js <<'EOF'
module.exports = [{ files: ["**/*.js"], languageOptions: { sourceType: "commonjs",
  globals: { require: "readonly", module: "writable", test: "readonly", expect: "readonly" } } }];
EOF
printf 'node_modules/\ncoverage/\n' > .gitignore
printf 'coverage/\n' > .prettierignore
npm pkg set scripts.test="jest" scripts.lint="eslint src" scripts.build="echo no build"
npx prettier --write . && npm run lint && npm test   # cả ba phải xanh trước khi bắt đầu
git add -A && git commit -m "chore: initial sandbox" && git push -u origin HEAD
```

Ở đây bootstrap đặt `smoke-command` là `npm run build`: nó chỉ thêm smoke test
(`npx jest smoke`, mẫu đường dẫn dạng tham số vị trí — chạy được cả Jest 29 lẫn 30) khi
có file như `test/smoke.test.js`.

Sau đó làm theo [ADD-TO-PROJECT.md](ADD-TO-PROJECT.vi.md) với repo này (template mặc định
đã là Node + Jest nên gần như không phải sửa lệnh).

### 8.2 Kịch bản nên thử

| Kịch bản | Cách làm | Kỳ vọng |
|---|---|---|
| Issue thiếu thông tin | Mở issue *Feature* chỉ ghi Goal mơ hồ, Acceptance criteria "làm cho tốt" | Nhãn `awaiting-clarification` + ≤3 câu hỏi/vòng (Socratic, 5 Whys, 5W1H, ví dụ/phản ví dụ… tuỳ chỗ hổng). Trả lời bằng comment → triage chạy lại |
| Không trả lời đủ | Trả lời lạc đề 5 lần | Nhãn `needs-human`, pipeline dừng |
| Đổi yêu cầu | Sửa nội dung issue đã `ready-for-plan` | Triage chạy lại, đếm vòng hỏi từ 0; PR agent cũ (nếu có) bị gắn `needs-human` |
| Huỷ | Đóng issue | Build đang chạy không push/mở PR; PR đã mở không được fix hay merge |
| Issue đủ ý, size S | "slugify bỏ dấu tiếng Việt", kèm 2–3 acceptance criteria cụ thể, rồi `/pipeline:build N` trong Claude Code | `ready-for-plan` → PR `agent/issue-N` có `Closes #N` |
| PR xanh + review approve | Chờ CI và *Agent Review* xong | Merge gate squash vào `main` (`develop` với gitlab-flow), xoá branch, đóng issue |
| PR đỏ | Đẩy thêm một commit làm hỏng test lên branch agent | Merge gate comment `/pipeline:build pr P`; chạy lệnh đó → bản sửa được push. Với `AGENT_AUTO_BUILD=true`: `fix` → agent commit sửa; sau 3 lần → `needs-human` |
| PR rủi ro cao | Gắn nhãn `risk:high` vào PR agent | Merge gate trả `blocked`, không merge |
| Smoke fail sau merge | Đặt `smoke-command: "false"` trong `agent-merge-gate.yml` | Sau merge có PR `revert/pr-N` mang `needs-human` |
| Release | Merge PR release (gitlab-flow: trước đó merge PR promotion `develop` → `main` bằng merge commit) | tag + GitHub Release; với gitlab-flow Branch Sync merge ngược về `develop` |

### 8.3 Xem agent đã làm gì

- **Actions → run → Summary**: quyết định của triage/gate, chi phí Claude, số lượt, thời gian.
- **Artifacts** của run: `transcript-*` là toàn bộ hội thoại của Claude, tải về để soi.
- Issue `pipeline-usage` (từ *Agent Usage Report*, hằng tuần hoặc chạy tay): tổng phút
  Actions và chi phí Claude.

## 9. Chi phí và giới hạn

- **Phút Actions:** mỗi issue thường gồm triage (1–3 phút/vòng), build (5–45 phút),
  CI, review (2–15 phút), merge gate. Giới hạn `timeout-minutes`/`max-turns` trong caller
  workflow chặn run chạy quá lâu. Theo dõi bằng *Agent Usage Report*.
- **Claude:** mặc định dùng model `sonnet`. Chi phí mỗi run nằm trong Step Summary.
  Với API key, đặt spend limit ở Console; với OAuth token, run bị giới hạn bởi hạn mức gói.
- **An toàn:** agent không cầm token push; mọi nhãn/merge/push do bash của workflow thực
  hiện theo JSON Claude trả về. `risk:high` không bao giờ được tự build hay tự merge.
  Mọi nhánh lỗi kết thúc bằng `needs-human`. Xem [ARCHITECTURE.md](ARCHITECTURE.vi.md).

**Tiếp theo:** [thêm pipeline vào dự án](ADD-TO-PROJECT.vi.md).
