# Kiến trúc pipeline

## Luồng tổng thể

```
 Issue (template: Goal / Constraints / Acceptance criteria)  ── label needs-triage
   │
   ▼  agent-triage.yml ─ uses ─▶ triage.yml
   │     Claude (read-only) trả JSON {decision, score, type, priority, risk, size, questions…}
   │     workflow áp nhãn / comment / GitHub Projects theo JSON đó
   │     ├─ clarify      → awaiting-clarification, hỏi ≤3 câu (tối đa max-rounds vòng)
   │     ├─ needs-human  → dừng
   │     ├─ reject       → comment / đóng nếu trùng
   │     └─ ready        → ready-for-plan (+ Projects: Priority, Size)
   │                        risk≠high && size≤M → workflow_dispatch agent-implement.yml
   ▼
 agent-implement.yml ─ uses ─▶ implement.yml (mode=implement)
   │     branch agent/issue-N · plugin pipeline@agent-toolkit
   │     /pipeline:implement-issue N → sub-agent planner → sub-agent implementer → commit
   │     workflow push + gh pr create "Closes #N" (label agent, draft nếu chưa xong)
   ▼
 PR → develop ──┬─▶ ci.yml ─ uses ─▶ quality.yml   lint → format → test → coverage ≥ develop
                │                                   PR title · Gitleaks · Semgrep
                └─▶ agent-review.yml ─ uses ─▶ review.yml   sub-agent reviewer,
                                                commit status agent/review trên head SHA
   ▼  (workflow_run: completed của CI hoặc Agent Review)
 agent-merge-gate.yml ─ uses ─▶ merge-gate.yml
   │   đọc mọi check run + commit status của head SHA qua Checks/Statuses API
   │   ├─ wait    → còn check đang chạy / thiếu agent/review
   │   ├─ blocked → needs-human, risk:high, do-not-merge, conflict, title sai
   │   ├─ fix     → implement.yml mode=fix (log CI + review findings)
   │   │             circuit breaker: ≥ max-fix-attempts → needs-human, dừng
   │   └─ merged  → squash, xoá branch, đóng issue
   │                 → smoke test trên develop; fail → PR revert (needs-human)
   ▼
 develop ──(bạn review, merge tay)──▶ main ─▶ release.yml (release-please: version,
                                               CHANGELOG, tag, build, upload artifact)
```

Guardrail chạy song song: transcript mỗi lần Claude chạy được upload làm artifact
(`transcript-<agent>-<n>`), mỗi job agent ghi chi phí/lượt/thời gian vào Step Summary,
và `usage-report.yml` cập nhật hằng tuần một issue tổng hợp phút Actions + chi phí Claude.
`workflows/ci-doctor.md` (gh-aw) bắt lỗi CI trên `develop`/`main` và biến nó thành issue
`needs-triage` để quay lại đầu pipeline.

## Nguyên tắc thiết kế

1. **Claude quyết định, workflow thực thi.** Triage và review trả JSON theo
   `--json-schema`; nhãn, comment, merge, push đều do bash xác định. Một issue bị
   prompt-injection tối đa chỉ chọn sai nhãn — giống mô hình *safe-outputs* của gh-aw.
2. **Agent không cầm token push.** `actions/checkout` với `persist-credentials: false`,
   `git push`/`git remote`/`git config`/`git reset`… nằm trong `--disallowedTools`.
   Push và tạo PR là bước riêng sau khi Claude kết thúc.
3. **Trạng thái gắn vào SHA.** Review ghi commit status trên head SHA, merge gate dùng
   `--match-head-commit`, fix-mode bỏ qua nếu PR đã có commit mới → không bao giờ merge
   hay sửa dựa trên kết quả cũ.
4. **Dừng về phía con người.** Mọi nhánh lỗi (hết vòng hỏi, circuit breaker, conflict,
   smoke fail, không có commit) đều kết thúc bằng nhãn `needs-human`, và mọi workflow
   agent bỏ qua issue/PR mang nhãn đó.
5. **Toàn bộ logic nằm trong toolkit.** Repo dự án chỉ có caller YAML mỏng + `CLAUDE.md`,
   nên cập nhật toolkit = cập nhật mọi dự án (hoặc ghim `@v1` để kiểm soát).

## Những "bẫy" của GitHub đã được xử lý

| Bẫy | Hệ quả nếu bỏ qua | Cách xử lý trong toolkit |
|---|---|---|
| Sự kiện do `GITHUB_TOKEN` tạo (push, PR, label, merge) **không kích hoạt workflow khác** (trừ `workflow_dispatch`/`repository_dispatch`) | PR của agent không chạy CI, merge không chạy smoke, nhãn `ready-for-plan` không khởi động build | Khuyến nghị GitHub App (`AGENT_APP_ID`/`AGENT_APP_PRIVATE_KEY`). Không có App: triage *dispatch* agent-implement, implement/merge-gate *dispatch* `ci.yml`, smoke test chạy ngay trong merge-gate |
| Free + private repo không có branch protection / rulesets | Auto-merge gốc không gate được theo check | `merge-gate.yml` tự kiểm Checks + Statuses API rồi `gh pr merge --match-head-commit` |
| `Closes #N` chỉ tự đóng issue khi merge vào **default branch** | Issue treo sau khi merge vào `develop` | merge-gate đóng issue tường minh |
| `workflow_run`, `schedule`, `workflow_dispatch` chỉ đọc workflow ở **default branch** | Caller đặt ở `develop` không bao giờ chạy | Commit caller vào default branch (xem [ADD-TO-PROJECT §7](ADD-TO-PROJECT.md#7-chọn-default-branch)) |
| `claude-code-action` từ chối actor là bot | Review/fix không chạy trên PR do App tạo | input `allowed-bots` (mặc định `*`, phù hợp repo private) |
| Projects v2 của **user** không nhận `GITHUB_TOKEN` hay GitHub App | Không thêm được item | secret `PROJECT_TOKEN` (classic PAT, scope `project`, `repo`) |
| CodeQL cần Advanced Security trên repo private | Không có SAST | Semgrep CLI (chỉ finding mới so với base) + Gitleaks + Dependabot |
| `gitleaks-action` cần license cho repo thuộc **organization** | Job fail | secret `GITLEAKS_LICENSE` (miễn phí đăng ký), không cần với tài khoản cá nhân |

## Vì sao pipeline chính không viết bằng gh-aw

`gh-aw` biên dịch mỗi workflow Markdown thành `.lock.yml` *trong repo đích*
(`gh aw add` + `gh aw compile`), nên không thể gọi bằng `uses: …@v1` như Giai đoạn 9
yêu cầu, và mô hình safe-outputs của nó không có sẵn các bước push/merge/circuit breaker
cần cho vòng build. Vì vậy:

- **Pipeline có gate** (triage → build → review → merge → release): reusable workflow
  + `anthropics/claude-code-action@v1`, mượn nguyên tắc read-only + safe-outputs của gh-aw.
- **Agent quan sát, không gate** (`workflows/ci-doctor.md`, và các workflow khác từ
  `githubnext/agentics` nếu muốn): dùng gh-aw, cài bằng
  `gh aw add kokoroou/agent-toolkit/ci-doctor`.

## Nhãn

| Nhóm | Nhãn |
|---|---|
| Trạng thái issue | `needs-triage` → `awaiting-clarification` → `ready-for-plan`; `needs-human` |
| Điều khiển | `agent:implement` (người gắn để chạy build), `agent` (PR do agent tạo, đủ điều kiện auto-merge), `do-not-merge`, `revert` |
| Phân loại | `type:*`, `priority:P0..P3`, `risk:low/medium/high`, `size:XS..XL` |

`risk:high` không bao giờ được auto-implement hay auto-merge.
