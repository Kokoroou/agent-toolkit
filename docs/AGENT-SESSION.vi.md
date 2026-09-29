# Phiên agent trên máy bạn hoặc trên Claude cloud

[English](AGENT-SESSION.md) · **Tiếng Việt**

Đây là cách mặc định để thi công một issue: bạn tự chạy skill `/pipeline:build` của plugin
`pipeline` trên máy mình hoặc trong một phiên Claude Code cloud, với đầy đủ harness của bạn
(tool, hook, sandbox), và xem nó làm việc trực tiếp. (Build agent trên GitHub Actions là
lựa chọn tuỳ chọn, xem ADD-TO-PROJECT §3.4.) Script `scripts/agent-session.sh` (lệnh cài chép vào dự án) lo hai thứ
mà phiên kiểu này cần nhưng không được đưa vào git:

- **Secret** (`.env`): commit ở dạng **đã mã hoá** bằng
  [age](https://github.com/FiloSottile/age) thành `.env.age`, giải mã khi phiên bắt đầu.
- **File không commit** (dữ liệu test, log, output debug): để trên storage ngoài qua
  [rclone](https://rclone.org) (Backblaze B2, Google Drive hoặc bất kỳ backend nào rclone
  hỗ trợ). Script tải xuống trước phiên và lưu lên sau phiên.

Cả hai được thiết kế để agent không thể dùng chúng làm công cụ chống lại người khác. Nếu
agent hiểu nhầm yêu cầu hay bị prompt injection dẫn dắt, nó vẫn không có credential của
storage và không có đường mạng tới storage.

- [1. Tổng quan](#1-tổng-quan)
- [2. Thiết lập một lần](#2-thiết-lập-một-lần)
- [3. Storage: Backblaze B2 hoặc Google Drive](#3-storage-backblaze-b2-hoặc-google-drive)
- [4. Phiên trên máy bạn](#4-phiên-trên-máy-bạn)
- [5. Phiên trên Claude cloud](#5-phiên-trên-claude-cloud)
- [6. Sandbox đảm bảo gì, không đảm bảo gì](#6-sandbox-đảm-bảo-gì-không-đảm-bảo-gì)
- [7. Lệnh và cấu hình](#7-lệnh-và-cấu-hình)

## 1. Tổng quan

```
bạn (ngoài sandbox)                         Claude (trong sandbox)
───────────────────                         ──────────────────────
giải mã .env.age → .env        ─┐
rclone pull → .agent-local/in   ├─▶  đọc .env, .agent-local/in/
                                │     viết code + commit, ghi .agent-local/out/
                                │     mạng: chỉ GitHub + registry gói
                                │     không có key age, rclone config, host storage
review diff, push, mở PR       ◀┘
save: kiểm tra + xác nhận → rclone push (key chỉ ghi) → sessions/<giờ>-<branch>/
```

| Thứ gì | Nằm ở đâu | Ai dùng được |
|---|---|---|
| `.env` | File thường trong thư mục làm việc, bị git ignore | Bạn và agent (test cần nó) |
| `.env.age` + `.age-recipients` | Commit | Ai cũng thấy; chỉ người có key trong danh sách giải mã được |
| Private key age | `~/.config/agent-session/age.key` (máy bạn) · biến môi trường `AGE_SECRET_KEY` (cloud) | Chỉ script này; ở máy bạn, agent bị chặn đọc |
| rclone config (key storage) | Chỉ ở `~/.config/rclone/` trên máy bạn | Chỉ script này, ngoài sandbox. Không bao giờ đưa lên cloud |
| `.agent-local/in/`, `.agent-local/out/` | Thư mục làm việc, bị git ignore | Agent đọc `in/`, ghi `out/`; chỉ bạn chạy `save` |

## 2. Thiết lập một lần

Cài [age](https://github.com/FiloSottile/age#installation) (`brew install age`,
`apt install age`, `winget install FiloSottile.age`). Nếu dùng storage thì cài thêm
[rclone](https://rclone.org/install/) và
[gitleaks](https://github.com/gitleaks/gitleaks#installing). Trên Windows hãy dùng WSL2,
vì sandbox của Claude Code không chạy trên Windows thuần.

Lệnh cài chép `scripts/agent-session.sh` và `.claude/settings.json` vào dự án. Nếu dự án
được cài trước khi có tính năng này, chạy `scripts/upgrade.sh`. Sau đó, trong thư mục dự
án:

```bash
scripts/agent-session.sh init       # key age, .age-recipients, .agent-session.conf, .gitignore
$EDITOR .env                        # điền secret
scripts/agent-session.sh encrypt    # → .env.age
git add .age-recipients .agent-session.conf .gitignore .env.age && git commit -m "chore: encrypted env"
```

Sao lưu `~/.config/agent-session/age.key` vào password manager. Mất key này thì không giải
mã được `.env.age`.

**Máy khác:** chạy `init` trên máy đó rồi commit dòng mới được thêm vào `.age-recipients`.
Sau đó, trên một máy đã giải mã được, chạy `encrypt` để file được mã hoá lại cho cả key mới.

**Đổi một secret:** sửa `.env`, chạy `encrypt`, rồi commit `.env.age`. Nếu nội dung không
đổi, `encrypt` giữ nguyên `.env.age` để diff không bị nhiễu.

## 3. Storage: Backblaze B2 hoặc Google Drive

Script dùng được với mọi remote của rclone. Nó dùng hai remote, và cấu hình giữ chúng là
hai key riêng để mỗi key chỉ có đúng quyền cần thiết:

- `PULL_REMOTE`: chỉ đọc, chứa các file phiên cần lúc bắt đầu.
- `PUSH_REMOTE`: chỉ ghi nếu backend cho phép, chứa những gì phiên tạo ra.

### Backblaze B2 (khuyên dùng: key giới hạn được theo thư mục và theo quyền)

Gói miễn phí: 10 GB lưu trữ và một hạn mức tải xuống miễn phí mỗi ngày
([bảng giá](https://www.backblaze.com/cloud-storage/pricing)).

1. Tạo một bucket **private**, ví dụ `my-agent-data`. Lifecycle để *Keep all versions*
   (mặc định), nên ghi đè nhầm cũng không mất dữ liệu.
2. Vào **App Keys → Add a New Application Key**, tạo hai lần:

   | Key | Bucket | File name prefix | Quyền |
   |---|---|---|---|
   | `myapp-pull` | `my-agent-data` | `myapp/shared/` | **Read Only** |
   | `myapp-push` | `my-agent-data` | `myapp/sessions/` | **Write Only** |

   Không cần tick *Allow List All Bucket Names*. Cả hai key đều không tạo được link chia sẻ,
   vì quyền `shareFiles` của B2 không nằm trong Read Only hay Write Only.
3. Thêm vào rclone:

   ```bash
   rclone config create b2-pull b2 account <keyID-pull> key <applicationKey-pull>
   rclone config create b2-push b2 account <keyID-push> key <applicationKey-push>
   ```

4. Trong `.agent-session.conf`:

   ```
   PULL_REMOTE=b2-pull:my-agent-data/myapp/shared
   PUSH_REMOTE=b2-push:my-agent-data/myapp/sessions
   ```

### Google Drive (dùng được, nhưng key khó giới hạn hơn)

Miễn phí 15 GB, dùng chung với Gmail và Photos. rclone
[hỗ trợ Drive](https://rclone.org/drive/). Khác với B2, token Drive **không giới hạn được
trong một thư mục, cũng không tách được chỉ đọc / chỉ ghi**. Nó có mọi quyền mà OAuth scope
cho phép, và tài khoản đó tạo được link chia sẻ công khai. Vì vậy an toàn ở đây dựa hoàn
toàn vào việc agent không bao giờ chạm tới token:

- Token chỉ nằm trong rclone config trên máy bạn.
- Sandbox chặn đọc file đó và chặn `*.googleapis.com`.
- Token không bao giờ được đặt vào môi trường cloud.

Các bước:

1. Tạo một thư mục, ví dụ `agent-data/myapp`, rồi lấy ID của nó từ URL.
2. Tạo remote với scope hẹp nhất dùng được:

   ```bash
   # drive.file: rclone chỉ thấy file do chính rclone tạo, nên mọi thứ phải đi qua rclone
   rclone config create gdrive drive scope drive.file root_folder_id <folder-id>
   ```

   Dùng `scope drive` nếu bạn muốn kéo thả file vào thư mục từ giao diện web Drive rồi pull
   về. Khi đó `root_folder_id` chỉ là thư mục bắt đầu, không phải ranh giới quyền.
3. Muốn file trên Drive cũng không đọc được, bọc remote bằng
   [`rclone crypt`](https://rclone.org/crypt/) để mã hoá phía client.
4. Trong `.agent-session.conf`:

   ```
   PULL_REMOTE=gdrive:shared
   PUSH_REMOTE=gdrive:sessions
   ```

Các backend khác của rclone, như Cloudflare R2, S3 hay OneDrive, cắm vào theo cùng cách.
Nếu backend bạn thêm có host chưa nằm trong `DENIED_DOMAINS` (xem §7), hãy thêm vào đó.

## 4. Phiên trên máy bạn

Cần Claude Code v2.1.219 trở lên. Trên Linux/WSL2 cần thêm `bubblewrap` và `socat`
(`sudo apt install bubblewrap socat`); macOS không cần cài gì thêm.

```bash
scripts/agent-session.sh run                         # tương tác
scripts/agent-session.sh run -- --permission-mode auto
# trong Claude: /pipeline:build 42   (hoặc: "thi công issue 42"; PR đỏ: /pipeline:build pr 57)
```

Skill tạo branch `agent/issue-42`, lập kế hoạch, viết code và chạy kiểm tra. Sandbox chặn
`git push` và `gh pr create`, nên skill ghi tiêu đề và nội dung PR vào `.agent-local/pr.md`
rồi bảo bạn thoát Claude.

`run` làm những việc sau:

1. Ghi checksum các file nó tin tưởng: `.agent-session.conf`, `.age-recipients`,
   `scripts/agent-session.sh` và `.claude/settings.json`. Checksum được lưu ngoài dự án,
   chỗ sandbox không ghi được.
2. Giải mã `.env.age` và pull `PULL_REMOTE` về `.agent-local/in/`.
3. Chạy `claude --settings <file sinh ra>`:
   - Xoá `AGE_*`, `RCLONE_*`, `B2_APPLICATION_KEY*` và `AGENT_SESSION_*` khỏi môi trường
     của Claude.
   - Sandbox là bắt buộc (`failIfUnavailable`, không cho chạy lại ngoài sandbox).
   - Mạng theo allowlist chặt: GitHub cùng các registry npm, PyPI, Go và crates. Host của
     storage còn nằm trong danh sách chặn.
   - Chặn đọc key age và rclone config.
   - Chặn ghi `.git/hooks`, `.git/config` và các file tin tưởng.
   - Chặn `rclone`, `age`, `WebFetch`, `git push`, `curl`/`wget`, và các lệnh `gh` có thể
     đăng thứ gì đó lên (gist, release, comment, tạo PR…).

   Xem file chính xác bằng `scripts/agent-session.sh settings`.
4. Khi Claude thoát và có `.agent-local/pr.md`, chạy `publish`: từ chối nếu file tin tưởng
   bị sửa hoặc còn thay đổi chưa commit, hiện các commit, diff stat và mọi thay đổi trong
   `.github/workflows`, rồi sau khi bạn xác nhận thì push branch (bỏ qua git hook) và mở PR
   có `Closes #N` với nhãn `agent` — hoặc, khi sửa PR, push và comment tóm tắt. Bạn cũng có
   thể tự chạy `scripts/agent-session.sh publish` sau.
5. Khi `.agent-local/out/` có file, hỏi bạn có muốn `save` không.

`save` từ chối upload khi:

- Một file tin tưởng bị thay đổi trong phiên. Review xong thì chạy lại với
  `--trust-changes`.
- `out/` chứa thứ khác file thường (symlink, device…), hoặc lớn hơn `MAX_SAVE_MB`.
- `gitleaks` tìm thấy secret trong đó.

Nếu không có vấn đề gì, `save` liệt kê file và đích đến rồi hỏi xác nhận. File được upload
vào một thư mục mới: `sessions/<giờ UTC>-<branch>/`.

Muốn theo dõi phiên trên máy từ điện thoại: gõ `/remote-control` trong Claude.

**macOS:** `gh` có thể lỗi TLS trong sandbox Seatbelt. Khi đó thêm vào `.agent-session.conf`
dòng `EXCLUDED_COMMANDS=gh issue view *, gh pr view *`. Chỉ hai lệnh chỉ đọc này sẽ chạy
ngoài sandbox.

## 5. Phiên trên Claude cloud

Phiên cloud chạy trong một VM do Anthropic quản lý. Setup script, hook, lệnh của bạn và
agent đều dùng chung VM đó, nên thứ gì đặt vào môi trường thì agent cũng đọc được. Thiết kế
là:

- Cho nó **key age** (test đằng nào cũng cần secret).
- **Không cho credential storage nào**, nên nó không có gì để upload.

1. Tạo một key riêng cho cloud để thu hồi riêng được:

   ```bash
   scripts/agent-session.sh cloud-key claude-cloud
   git add .age-recipients .env.age && git commit -m "chore: add cloud recipient" && git push
   ```

2. Tại claude.ai/code, mở menu environment trên thanh tiêu đề của phiên, chọn **Edit**, rồi:
   - **Environment variables**: `AGE_SECRET_KEY=AGE-SECRET-KEY-1…` (dòng mà `cloud-key` in
     ra).
   - **Setup script**: `apt-get update && apt-get install -y age || true`.
   - **Network access**: xem bên dưới.
3. Mở phiên trên repo. `.claude/settings.json` của dự án có hook `SessionStart` chạy
   `agent-session.sh decrypt --if-key`, nên `.env` có sẵn trước khi agent bắt đầu. Cùng hook
   đó không làm gì trong CI hoặc trên máy không có key.
4. Gõ `/pipeline:build 42` (hoặc "thi công issue 42"). Phiên cloud tự push được, nên sau
   khi bạn xác nhận nó push và mở PR `agent` luôn. Proxy GitHub của cloud chỉ cho push lên
   branch của phiên, nên PR đi từ branch đó thay vì `agent/issue-42`; review và merge gate
   vẫn chạy như thường (chúng dựa vào nhãn `agent` và `Closes #42`). Với
   `/pipeline:build pr 57`, phiên phải push được lên branch của PR; nếu bị từ chối, skill
   dừng và báo — khi đó sửa PR đó từ máy bạn.

**Mạng trên cloud (đã tra tài liệu chính thức).** Hộp thoại environment có 4 mức
([tài liệu](https://code.claude.com/docs/en/cloud-environments#access-levels)):

| Mức | Kết nối ra ngoài |
|---|---|
| None | Không có gì qua mạng của phiên |
| **Trusted** (mặc định) | Allowlist cố định: registry gói, GitHub, SDK cloud |
| Full | Mọi domain |
| **Custom** | Mỗi dòng một domain (`*.` ở đầu khớp subdomain); tuỳ chọn gộp thêm danh sách Trusted |

Một số luồng đi vòng qua mức bạn chọn:

- GitHub, qua proxy riêng chỉ cho `git push` lên branch của phiên.
- Các MCP connector bạn bật.
- Host của **API credentials** trong environment (gói Pro/Max).
- API của Anthropic.

Danh sách Trusted có `*.googleapis.com`, `*.amazonaws.com` và
`*.r2.cloudflarestorage.com`, nên phiên ở mức Trusted **vẫn kết nối mạng được tới Google
Drive, S3 và R2**. Điều đó chỉ an toàn vì environment không chứa credential storage nào.
Hãy giữ như vậy:

- Không đặt rclone config, key B2/Drive hay bất kỳ token storage nào vào environment
  variables.
- Không thêm host storage vào **API credentials**. Proxy sẽ gắn key thay cho agent, đúng
  kiểu "storage thành công cụ" mà thiết kế này tránh.
- Không bật MCP connector Google Drive cho phiên làm việc thi công.
- Chặt nhất: chọn **Custom**, bỏ tick "Also include default list", và chỉ liệt kê registry
  dự án cần, ví dụ `registry.npmjs.org`.

**Output trên cloud** nằm trên VM và mất khi VM bị thu hồi. Bảo Claude gửi file cho bạn
(xem và tải trong app Claude). Muốn lưu trữ thì tải về máy rồi chạy
`scripts/agent-session.sh save` trên máy: việc lưu luôn phải qua tay người.

## 6. Sandbox đảm bảo gì, không đảm bảo gì

**Trên máy bạn:**

- Sandbox của hệ điều hành đảm bảo, cho mọi lệnh agent chạy và tiến trình con của nó:
  - không kết nối tới host ngoài allowlist;
  - không đọc được key age hay rclone config;
  - không ghi được git hook hay các file tin tưởng.
- Script này đảm bảo:
  - credential storage không bao giờ vào môi trường của Claude;
  - chỉ người mới upload được, sau khi kiểm tra, và bằng key chỉ ghi nếu backend hỗ trợ.

**Rủi ro còn lại:**

- **GitHub vẫn truy cập được.** Agent có thể đưa dữ liệu vào commit. Review diff trước khi
  push; `/pipeline:build` hỏi trước khi push, và trong `run` nó không push được: `publish`
  cho bạn xem các commit trước.
- **Code agent viết sẽ chạy sau đó, ngoài sandbox**, khi bạn tự chạy test, git hook (husky…)
  hay script build. Hãy review trước, như với mọi PR.
- **Agent đọc được `.env`** (test cần nó). Chỉ để credential dev/test trong đó, không bao
  giờ để credential production.
- **Trên cloud, agent đọc được `AGE_SECRET_KEY`.** Key này chỉ giải mã được những gì vốn đã
  có trong `.env`, nên không cho thêm quyền gì. Nếu environment bị chia sẻ hoặc bị lộ, thu
  hồi theo hướng dẫn mà `cloud-key` in ra.
- Bỏ một recipient không làm các commit cũ hết mã hoá được. **Đổi secret** khi mất key.

## 7. Lệnh và cấu hình

| Lệnh | Làm gì |
|---|---|
| `init` | Tạo key age (mỗi máy một lần), thêm vào `.age-recipients`, tạo `.agent-session.conf`, cập nhật `.gitignore` |
| `cloud-key [nhãn]` | Key mới cho environment cloud: thêm recipient, mã hoá lại, in secret đúng một lần |
| `encrypt [--trust-changes]` | `SECRET_FILES` → `<file>.age` (dạng ASCII; bỏ qua nếu nội dung không đổi) |
| `decrypt [--force] [--if-key]` | `<file>.age` → `<file>`. Giữ file local khác nội dung trừ khi có `--force`. `--if-key` không làm gì khi thiếu key hoặc thiếu `age` |
| `pull` | `PULL_REMOTE` → `IN_DIR` |
| `run [--no-pull] [-- <tham số claude>]` | decrypt + pull + Claude trong sandbox + hỏi publish và save |
| `publish [--yes] [--trust-changes]` | Push branch hiện tại và mở PR theo `.agent-local/pr.md` (do `/pipeline:build` ghi); khi sửa PR thì push và comment. Hỏi trước khi làm |
| `save [--yes] [--trust-changes]` | Kiểm tra rồi upload `OUT_DIR` lên `PUSH_REMOTE/<stamp>/`. `--yes` bắt buộc phải có gitleaks |
| `settings` | In settings sandbox được sinh ra |

`.agent-session.conf` được commit và chỉ đọc như dữ liệu. Khoá lạ bị báo lỗi. Giá trị là
danh sách từ cách nhau bởi dấu cách.

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `SECRET_FILES` | `.env` | Các file được giữ mã hoá thành `<file>.age` |
| `PULL_REMOTE` / `PUSH_REMOTE` | trống | rclone `remote:path`; để trống = bỏ qua |
| `IN_DIR` / `OUT_DIR` | `.agent-local/in` / `.agent-local/out` | Tương đối với gốc dự án, bị git ignore |
| `MAX_SAVE_MB` | `200` | `save` từ chối nếu lớn hơn |
| `ALLOWED_DOMAINS` | GitHub + registry npm/yarn, PyPI, Go, crates | Allowlist của sandbox khi `run` |
| `EXTRA_ALLOWED_DOMAINS` | trống | Thêm vào allowlist, ví dụ `registry.example.com` |
| `DENIED_DOMAINS` | B2, Google APIs/Drive, R2, S3, Dropbox, Box, OneDrive | Luôn bị chặn, kể cả khi một mục trong allowlist khớp |
| `ALLOW_WEBFETCH` | `false` | Cho tool WebFetch của Claude mở trang web khi `run` |
| `EXCLUDED_COMMANDS` | trống | Các lệnh chạy **ngoài** sandbox, cách nhau bằng dấu phẩy. Để trống trừ khi có công cụ không chạy được trong sandbox |

Biến môi trường: `AGE_SECRET_KEY` (nội dung key, được ưu tiên) và `AGENT_SESSION_KEY_FILE`
(đường dẫn key, mặc định `~/.config/agent-session/age.key`).
