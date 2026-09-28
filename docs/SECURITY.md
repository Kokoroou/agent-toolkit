# Đánh giá bảo mật agent-toolkit

_Rà soát: 2026-09 · phạm vi: `.github/workflows/*`, `templates/`, `scripts/`, plugin `pipeline`._

## Tóm tắt

Thiết kế nền tảng khá tốt: quyền `permissions` khai báo tối thiểu theo từng job,
`persist-credentials: false` ở mọi checkout, Claude không được `git push` (workflow tự
push), triage chỉ trả về JSON có schema rồi workflow áp dụng một cách xác định, dữ liệu
không tin cậy (tiêu đề PR, output của Claude) đi qua biến môi trường thay vì nội suy
`${{ }}` vào script. Điểm yếu còn lại tập trung ở **job build (`implement.yml`)**: Claude
chạy trên cùng runner, cùng job với token có quyền ghi.

| # | Mức | Vấn đề | Trạng thái |
|---|-----|--------|-----------|
| 1 | Cao | `implement.yml`: bước Claude có `GH_TOKEN` (contents/actions **write**) trong env; `extra-allowed-tools` như `Bash(npm run:*)` + quyền `Edit` cho phép chạy mã tùy ý → prompt injection từ issue có thể lấy token | **Đề xuất** (xem dưới) |
| 2 | Cao | `implement.yml`: bước publish chạy `git commit/push` với token sau khi agent có thể đã sửa `.git/config`, hook, `$GITHUB_ENV`, `$GITHUB_PATH` | **Đề xuất** (cùng cách sửa #1) |
| 3 | Cao | Issue của người ngoài (repo public) được triage `ready` sẽ tự khởi động build agent có quyền ghi | **Đã sửa**: `auto-implement-trusted-only` (mặc định `true`) — chỉ OWNER/MEMBER/COLLABORATOR |
| 4 | Trung bình | `merge-gate.yml`: smoke test chạy mã vừa merge trong job có `contents: write` + App token, rồi mở revert PR trên cùng runner | **Đã sửa**: tách job `smoke` (read-only) và `revert` (runner sạch) |
| 5 | Trung bình | `quality.yml`: `GH_TOKEN` đặt ở mức job nên lệnh lint/test của dự án cũng nhận token | **Đã sửa**: chỉ bước so coverage nhận token |
| 6 | Trung bình | `self-test.yml` tải script actionlint từ nhánh `main` (supply chain) | **Đã sửa**: tải từ tag phát hành, ghim phiên bản |
| 7 | Trung bình | Action ghim theo tag (`@v5`), không theo SHA; tag có thể bị dời | **Đề xuất**: ghim SHA + Dependabot (đã thêm `.github/dependabot.yml` cho toolkit) |
| 8 | Thấp | `allowed-bots: "*"` mặc định — ổn với repo private, rộng với repo public | **Đề xuất**: với repo public đặt danh sách bot cụ thể |
| 9 | Thấp | Semgrep chạy image `semgrep/semgrep` không ghim phiên bản | **Đã sửa một phần**: cài bằng pipx, thêm input `semgrep-version` để ghim |
| 10 | Thấp | Lệnh `setup-command`/`smoke-command` được nội suy thẳng vào `run:` (zizmor `template-injection`, 9 chỗ) | Chấp nhận: giá trị do chủ repo gọi workflow đặt, không phải dữ liệu người dùng |
| 11 | Cao | Token GitHub App kế thừa **mọi** quyền của App (zizmor `github-app`) | **Đã sửa**: mỗi job xin đúng `permission-*` cần dùng; quyền *Workflows* chỉ xin khi `allow-workflow-changes: true` |
| 12 | Trung bình | `toolkit-release.yml` lưu credential trong `.git/config` khi checkout (zizmor `artipacked`) | **Đã sửa**: `persist-credentials: false`, push bằng token tường minh |
| 13 | Thấp | Template dùng `secrets: inherit` (zizmor `secrets-inherit`) — workflow được gọi thấy mọi secret của repo | **Đề xuất**: truyền tường minh `anthropic_api_key`, `agent_app_id`, … |
| 14 | Thấp | `agent-merge-gate.yml` dùng `workflow_run` (zizmor `dangerous-triggers`) | Chấp nhận: gate bỏ qua PR từ fork, kiểm tra head SHA, không checkout mã PR |

## Công cụ kiểm tra an ninh

| Công cụ | Ở đâu | Kiểm tra gì |
|---------|-------|-------------|
| Gitleaks | `quality.yml` (dự án) + `self-test.yml` (toolkit) | Secret lọt vào lịch sử git |
| Semgrep `p/default` | như trên | Lỗi bảo mật trong mã, chỉ báo phát hiện mới so với baseline |
| zizmor | `self-test.yml` (report-only) | Lỗ hổng GitHub Actions: template injection, quyền thừa, `pull_request_target`, credential persistence, action không ghim, cache poisoning |
| actionlint + shellcheck | `self-test.yml` | Cú pháp workflow, script nhúng |
| Dependabot | `.github/dependabot.yml` (toolkit), `templates/.github/dependabot.yml` (dự án) | Cập nhật action / thư viện, cảnh báo CVE |

Lần chạy zizmor 1.30.1 sau các bản sửa: còn 35 `unpinned-uses` (#7), 9
`template-injection` (#10), 8 `secrets-inherit` (#13), 1 `dangerous-triggers` (#14);
không còn `github-app` và `artipacked`.

zizmor đang ở chế độ **report-only** vì một số phát hiện là có chủ đích (ví dụ #10).
Sau khi rà các annotation, thêm file `.github/zizmor.yml` để bỏ qua các phát hiện đã chấp
nhận rồi bỏ `|| echo …` trong `self-test.yml` để biến nó thành cổng chặn.

## Đề xuất sửa #1 và #2: tách job build thành 3 job

Hiện tại một job làm tất cả: đọc context → cài dependency → Claude → push/mở PR. Mọi
thứ agent (hoặc mã agent viết) chạy đều có thể đọc token ghi và sửa môi trường của bước
push. Cách sửa triệt để (giống mô hình "safe outputs"):

1. **`prepare`** (quyền ghi, không chạy mã dự án): circuit breaker, nhãn, tính branch.
2. **`agent`** (`contents: read`, `issues: read`, `pull-requests: read`, `actions: read`):
   checkout, `setup-command`, Claude. Kết quả là `git bundle` các commit mới + JSON
   structured output, upload thành artifact. Không có token ghi nào trên runner này.
3. **`publish`** (quyền ghi, runner sạch): checkout base, `git fetch` từ bundle, kiểm tra
   bundle chỉ chứa commit nối tiếp `before` và không sửa `.github/workflows/**` (trừ khi
   được phép), rồi push + mở PR như hiện nay.

Cho tới khi làm việc này, nên: dùng GitHub App (token cấp theo repo, dễ thu hồi), giữ
`extra-allowed-tools` ở mức hẹp nhất có thể (tránh `Bash(npm run:*)` nếu không cần), và
để `auto-implement-trusted-only: true`.

**Thay đổi hành vi:** trước đây token App mang cả quyền *Workflows* nếu App có quyền đó.
Giờ agent chỉ push được thay đổi trong `.github/workflows/` khi caller đặt
`allow-workflow-changes: true` cho `implement.yml` (cả ở `agent-implement.yml` và job
`fix` của `agent-merge-gate.yml`).

## Node 24 trên GitHub Actions

GitHub chuyển runtime của JavaScript action từ Node 20 sang Node 24. Các action đã được
nâng lên bản chạy Node 24: `actions/checkout@v5`, `actions/setup-node@v5`,
`actions/upload-artifact@v5`, `actions/create-github-app-token@v3`,
`googleapis/release-please-action@v5`, `gitleaks/gitleaks-action@v3`.
`anthropics/claude-code-action@v1` là composite action nên không bị ảnh hưởng.
Template mặc định chuyển `npm test -- --testPathPattern=smoke` thành `npm test -- smoke`
vì Jest 30 đã bỏ cờ `--testPathPattern`.
