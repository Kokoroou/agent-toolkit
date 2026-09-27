# Cài đặt

## A. Một lần cho toolkit (Giai đoạn 0)

1. Repo `kokoroou/agent-toolkit` để **public**: caller ở repo private gọi được reusable
   workflow và `claude plugin marketplace add` clone được mà không cần PAT.
   Toolkit không chứa secret hay nghiệp vụ.
2. Trên máy bạn (tuỳ chọn, để dùng plugin khi làm việc tay và để thêm agent gh-aw):
   ```bash
   claude plugin marketplace add kokoroou/agent-toolkit
   claude plugin install pipeline@agent-toolkit
   gh extension install github/gh-aw
   ```
3. Tạo release đầu tiên: merge PR release-please mà `toolkit-release.yml` mở trên `main`
   → tag `v0.x.y` và tag di động `v0`. (Khi lên 1.0.0 sẽ có `v1`.)

## B. GitHub App cho agent (khuyến nghị mạnh)

Không có App, mọi push/PR/merge của agent dùng `GITHUB_TOKEN` và **không kích hoạt
workflow khác** — toolkit có đường vòng bằng `workflow_dispatch`, nhưng App sạch hơn
(CI chạy như PR thường, check hiện trên PR, smoke/CI chạy sau merge).

1. Settings → Developer settings → GitHub Apps → **New GitHub App**
   - Webhook: tắt. Homepage: URL bất kỳ.
   - Repository permissions: **Contents** RW, **Pull requests** RW, **Issues** RW,
     **Actions** RW, **Workflows** RW (nếu agent có thể sửa file workflow), **Metadata** R.
   - Where can this app be installed: *Only on this account*.
2. Generate private key (.pem). Install App vào các repo dự án.
3. Ở mỗi repo dự án (hoặc dùng chung qua org secrets nếu có): secret `AGENT_APP_ID`
   (App ID) và `AGENT_APP_PRIVATE_KEY` (nội dung .pem).

## C. Mỗi dự án (Giai đoạn 2–9)

```bash
git clone https://github.com/kokoroou/agent-toolkit /tmp/agent-toolkit
/tmp/agent-toolkit/scripts/bootstrap.sh ~/code/my-project --ref v0   # hoặc --ref main
```

Script chép caller workflow, issue/PR template, `dependabot.yml`, `CLAUDE.md` mẫu; ghim
`uses: …@<ref>`; tạo bộ nhãn và branch `develop` (cần `gh auth login`).

Sau đó:

1. **Sửa các khối `edit for your stack`** trong `.github/workflows/*.yml` (lệnh
   setup/lint/test/coverage/smoke, `extra-allowed-tools`) và điền `CLAUDE.md`.
   `coverage-command` phải in **số phần trăm ở dòng cuối stdout**, ví dụ:
   - Python: `pytest --cov=src --cov-report=term >&2 && coverage report --format=total`
   - Go: `go test -coverprofile=c.out ./... >&2 && go tool cover -func=c.out | tail -1 | awk '{print $3}'`
2. **Secrets** (Settings → Secrets and variables → Actions):
   | Secret | Bắt buộc | Ghi chú |
   |---|---|---|
   | `ANTHROPIC_API_KEY` *hoặc* `CLAUDE_CODE_OAUTH_TOKEN` | ✔ | OAuth token (`claude setup-token`) dùng hạn mức gói Claude thay vì tính tiền API |
   | `AGENT_APP_ID`, `AGENT_APP_PRIVATE_KEY` | khuyến nghị | mục B |
   | `PROJECT_TOKEN` | nếu dùng Projects | classic PAT, scope `project` + `repo` |
   | `GITLEAKS_LICENSE` | chỉ repo của org | |
3. **Settings → Actions → General → Workflow permissions**: *Read and write* và
   *Allow GitHub Actions to create and approve pull requests*.
4. **Default branch**: `workflow_run`, `schedule`, `workflow_dispatch` chỉ chạy file ở
   default branch. Hai lựa chọn:
   - Đặt `develop` làm default branch (đơn giản nhất: caller workflow sống ở đó, issue
     tự đóng khi merge), `main` chỉ nhận merge tay để release; **hoặc**
   - Giữ `main` là default và nhớ merge các thay đổi workflow sang `main`.
5. **GitHub Projects (Giai đoạn 3)**: tạo Project v2, thêm field single-select
   `Priority` (P0, P1, P2, P3) và `Size` (XS, S, M, L, XL); bỏ comment `project-owner` /
   `project-number` trong `agent-triage.yml`.
6. **Dependabot alerts**: Settings → Code security → bật *Dependabot alerts* và
   *security updates* (miễn phí cho repo private). Sửa ecosystem trong `dependabot.yml`.
7. **gh-aw CI doctor** (tuỳ chọn):
   ```bash
   gh aw add kokoroou/agent-toolkit/ci-doctor && gh aw compile
   gh aw secrets set ANTHROPIC_API_KEY   # hoặc theo hướng dẫn gh aw cho engine claude
   ```
8. Commit vào default branch, rồi thử: tạo issue từ template *Feature / change request*.

## D. Thử nghiệm trước khi dùng thật (cuối Giai đoạn 1)

Tạo repo private `kokoroou/agent-sandbox` với một dự án nhỏ có test (ví dụ một hàm
`slugify` + Jest), bootstrap như trên với `--ref main`, rồi chạy lần lượt:

| Kịch bản | Kỳ vọng |
|---|---|
| Issue thiếu acceptance criteria | `awaiting-clarification` + ≤3 câu hỏi; trả lời → triage chạy lại |
| Không trả lời đủ sau 3 vòng | `needs-human` |
| Issue đủ ý, size S | `ready-for-plan` → PR `agent/issue-N` với `Closes #N` |
| PR xanh + review approve | merge-gate squash vào `develop`, đóng issue |
| Cố ý làm hỏng test trong PR agent | merge-gate → `fix` → commit sửa; sau 3 lần → `needs-human` |
| Gắn `risk:high` vào PR | merge-gate `blocked` |
| `smoke-command: "false"` | sau merge có PR `revert/pr-N` |
| Merge `develop` → `main` | release-please mở release PR; merge → tag + release |

Xem Step Summary của từng run (quyết định của gate, chi phí Claude) và artifact
`transcript-*` khi cần soi agent đã làm gì.

## E. Ghim phiên bản (Giai đoạn 9)

- `bootstrap.sh --ref v1` ghim mọi `uses:` vào tag di động `v1` (nhận bản vá, không nhận
  breaking change). Ghim chặt hơn bằng `--ref v1.2.3` hoặc một commit SHA.
- Plugin được cài từ `toolkit-marketplace` (mặc định nhánh mặc định của toolkit). Để ghim
  luôn plugin, thêm vào các job gọi `triage.yml`, `implement.yml`, `review.yml`:
  ```yaml
  with:
    toolkit-marketplace: https://github.com/kokoroou/agent-toolkit.git#v1
  ```
