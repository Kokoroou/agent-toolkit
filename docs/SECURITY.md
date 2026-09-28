# Bảo mật agent-toolkit

_Rà soát: 2026-09 · phạm vi: `.github/workflows/*`, `templates/`, `scripts/`, plugin `pipeline`._

## Mô hình: Lethal Trifecta

Một agent LLM trở nên nguy hiểm khi có **cùng lúc** ba thứ
([Simon Willison](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/)):

- **P — dữ liệu riêng tư / quyền đặc biệt**: mã nguồn private, secret, token có quyền ghi;
- **U — nội dung không tin cậy**: issue, comment, diff PR, log CI — ai viết được là có
  thể chèn lệnh vào prompt;
- **X — kênh ra ngoài**: gọi mạng, hoặc hành động có tác dụng ngoài job (push, comment,
  merge).

Prompt injection không chặn được hoàn toàn bằng prompt, nên toolkit cắt ít nhất một
chân của mỗi agent **bằng cấu hình**, không dựa vào việc model "biết từ chối".

### Ma trận khả năng

| Agent | P: agent thấy gì | U: đọc nội dung gì | X: agent tác động ra ngoài bằng gì | Chân bị cắt |
|---|---|---|---|---|
| Triage (`triage.yml`) | Repo (đọc), token đọc issue | Issue + comment (ai cũng viết được trên repo public) | **Không có**: chỉ trả JSON theo schema; bash áp nhãn/comment. Không có Bash tùy ý, WebFetch, WebSearch | **X** |
| Review (`review.yml`) | Repo + PR (đọc) | Diff PR, mô tả PR | Chỉ inline comment trong PR + verdict JSON. Không chạy mã, không có mạng | **X** (chỉ còn kênh trong repo) |
| Build (`implement.yml`, job `agent`) | Repo (đọc), token **chỉ đọc**, API key Claude | Issue/PR của **collaborator** (mặc định), log CI | Có mạng khi chạy lệnh dự án (`npm run`…), nhưng **không** có token ghi; commit ra ngoài chỉ qua bundle được `publish` kiểm tra | **U** (tác giả tin cậy) + **P** (không token ghi) |
| Merge gate, publish, revert | Token ghi | Chỉ dữ liệu có cấu trúc | Merge, push | Không có LLM |

Với **repo private**, mọi người viết issue/comment đều là collaborator, nên các giới hạn
trên không đổi gì trong vận hành hằng ngày — chúng chặn trường hợp repo public, tài khoản
collaborator bị chiếm, hoặc nội dung độc hại lọt vào qua dependency/log.

### Build agent: 3 job

```
prepare (token ghi, không chạy mã dự án)  → circuit breaker, branch, commit bắt đầu (SHA)
agent   (token CHỈ ĐỌC)                   → setup dự án + Claude → git bundle + JSON
publish (token ghi, runner sạch)          → kiểm tra bundle → push → PR
```

`publish` coi mọi thứ từ `agent` là dữ liệu không tin cậy: JSON phải đúng schema, bundle
phải chỉ thêm commit nối tiếp đúng SHA mà `prepare` đã chọn, và không được sửa
`.github/workflows/` nếu caller không đặt `allow-workflow-changes: true`. Mọi thứ agent
(hoặc mã nó chạy) ghi lên runner — `.git/config`, hook, `$GITHUB_ENV`, `$GITHUB_PATH`,
binary giả — nằm lại ở runner của job `agent`, không chạm tới job push.

**Rủi ro còn lại (chấp nhận):** job `agent` vẫn có mạng (cần để `npm ci`, gọi API Claude),
nên một agent bị điều khiển có thể gửi *mã nguồn* ra ngoài. Chân U được giảm bằng
`auto-implement-trusted-only`; giữ `extra-allowed-tools` hẹp nhất có thể. Muốn cắt nốt
chân X thì cần runner tự host có tường lửa egress (chỉ cho `api.anthropic.com`,
`github.com`, registry gói).

## Các phát hiện và trạng thái

| # | Mức | Vấn đề | Trạng thái |
|---|-----|--------|-----------|
| 1 | Cao | Bước Claude của build agent có `GH_TOKEN` quyền ghi; `Bash(npm run:*)` + `Edit` = chạy mã tùy ý → lấy được token | **Đã sửa**: job `agent` chỉ có token đọc |
| 2 | Cao | Bước push chạy sau khi agent có thể sửa `.git/config`, hook, `$GITHUB_ENV`, `$GITHUB_PATH` | **Đã sửa**: push ở job `publish` trên runner sạch, từ bundle đã kiểm tra |
| 3 | Cao | Issue của người ngoài (repo public) được triage `ready` tự khởi động build agent | **Đã sửa**: `auto-implement-trusted-only` (mặc định `true`) |
| 4 | Cao | Token GitHub App kế thừa **mọi** quyền của App | **Đã sửa**: mỗi job xin đúng `permission-*`; *Workflows* chỉ khi `allow-workflow-changes: true` |
| 5 | Trung bình | Smoke test chạy mã vừa merge trong job có token ghi, revert PR trên cùng runner | **Đã sửa**: job `smoke` chỉ đọc, job `revert` riêng |
| 6 | Trung bình | `quality.yml`: lệnh lint/test của dự án nhận `GH_TOKEN` | **Đã sửa**: chỉ bước so coverage nhận token |
| 7 | Trung bình | Action ghim theo tag, tag có thể bị dời | **Đã sửa**: ghim SHA kèm comment phiên bản; Dependabot cập nhật |
| 8 | Trung bình | `self-test.yml` tải script actionlint từ nhánh `main` | **Đã sửa**: tải từ tag phát hành |
| 9 | Trung bình | `toolkit-release.yml` lưu credential khi checkout | **Đã sửa**: `persist-credentials: false`, push bằng token tường minh |
| 10 | Thấp | Template dùng `secrets: inherit` | **Đã sửa**: truyền đúng secret từng workflow cần |
| 11 | Thấp | Agent có thể dùng WebFetch/WebSearch làm kênh ra ngoài | **Đã sửa**: `--disallowedTools WebFetch,WebSearch` ở mọi agent |
| 12 | Thấp | `allowed-bots: "*"` | Giữ: phù hợp repo private (agent PR do bot tạo). Repo public nên đặt danh sách bot cụ thể |
| 13 | — | `setup-command`/`smoke-command` nội suy vào `run:` | Chấp nhận (giá trị do chủ repo đặt), ignore tại chỗ cho zizmor |
| 14 | — | `agent-merge-gate.yml` dùng `workflow_run` | Chấp nhận: bỏ PR từ fork, kiểm head SHA, không checkout mã PR |

## Công cụ kiểm tra an ninh

| Công cụ | Ở đâu | Kiểm tra gì |
|---------|-------|-------------|
| zizmor (chặn từ mức *medium*) | `self-test.yml`, cấu hình `.github/zizmor.yml` | Lỗ hổng GitHub Actions: template injection, quyền thừa, credential persistence, action không ghim SHA, action có lỗ hổng đã biết |
| Gitleaks | `quality.yml` (dự án) + `self-test.yml` (toolkit) | Secret lọt vào lịch sử git |
| Semgrep `p/default` | như trên | Lỗi bảo mật trong mã, chỉ báo phát hiện mới so với baseline |
| actionlint + shellcheck | `self-test.yml` | Cú pháp workflow, script nhúng |
| Dependabot | `.github/dependabot.yml`, `templates/.github/dependabot.yml` | Cập nhật action (kể cả SHA ghim) / thư viện, cảnh báo CVE |

## Thay đổi hành vi khi nâng cấp

- Agent chỉ push được thay đổi trong `.github/workflows/` khi caller đặt
  `allow-workflow-changes: true` (ở `agent-implement.yml` và job `fix` của
  `agent-merge-gate.yml`); nếu không, run dừng với nhãn `needs-human`.
- Issue do người không phải collaborator mở không được tự implement (repo private không
  bị ảnh hưởng). Tắt bằng `auto-implement-trusted-only: false`.
- Caller template truyền secret theo tên: `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`,
  `AGENT_APP_ID`, `AGENT_APP_PRIVATE_KEY`, `PROJECT_TOKEN` — đúng các tên `install.sh` đặt —
  và `GITLEAKS_LICENSE` (tự thêm nếu repo thuộc organization). Dự án đã cài có thể giữ `secrets: inherit`; cả hai cách
  đều chạy.

## Node 24 trên GitHub Actions

Mọi JavaScript action đã dùng bản chạy Node 24: `actions/checkout` v5, `setup-node` v5,
`upload-artifact` v6, `download-artifact` v7, `create-github-app-token` v3,
`release-please-action` v5, `gitleaks-action` v3 (`upload-artifact` v5 và
`download-artifact` v5/v6 vẫn là Node 20). `anthropics/claude-code-action` là composite
action, bên trong dùng `oven-sh/setup-bun` v2.2.0 (Node 24). Lệnh smoke mặc định dùng
`npm test -- smoke` vì Jest 30 đã bỏ cờ `--testPathPattern`.
