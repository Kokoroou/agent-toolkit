# Kế hoạch thi công — trạng thái

Bối cảnh: GitHub Free, repo private, Claude Code làm sub-agent, GitHub Actions làm CI,
auto-merge hoàn toàn khi CI pass. Toolkit dùng chung: `kokoroou/agent-toolkit`.

Ký hiệu: ✅ đã có trong repo · 👤 bạn cần làm trên GitHub/máy (không tự động được) ·
🔀 làm khác kế hoạch gốc, có lý do.

## Giai đoạn 0 — Nền tảng
- 👤 Repo `kokoroou/agent-toolkit` để public → [SETUP §A](SETUP.md#a-một-lần-cho-toolkit-giai-đoạn-0)
- 👤 `gh extension install github/gh-aw`
- ✅ Khảo sát `githubnext/agentics`: `ci-doctor` được chuyển thể thành
  [`workflows/ci-doctor.md`](../workflows/ci-doctor.md) (engine claude, lỗi CI trên
  develop/main → issue `needs-triage`). `issue-triage` và `pr-fix` được dùng làm tham khảo
  cho `triage.yml` / `implement.yml mode=fix` (mượn mô hình read-only + safe-outputs).
- 🔀 `verkyyi/github-agent-runner`: chưa khảo sát được trong phiên này. Vai trò
  planner → implementer → reviewer giữ đúng như kế hoạch; bước "spec" nằm ở triage.
- ✅ `anthropics/claude-code-action@v1` là nền gọi Claude ở mọi workflow agent.

## Giai đoạn 1 — Toolkit
- ✅ `.claude-plugin/marketplace.json` + `plugins/pipeline/`
  - 🔀 `CLAUDE.md` của plugin → skill [`pipeline-conventions`](../plugins/pipeline/skills/pipeline-conventions/SKILL.md):
    Claude Code **không** nạp `CLAUDE.md` nằm trong plugin; skill được nạp sẵn vào cả 3
    sub-agent (`skills:` frontmatter). Phần riêng của dự án (lệnh test, kiến trúc) nằm ở
    [`templates/CLAUDE.md`](../templates/CLAUDE.md) đặt tại root repo dự án.
  - ✅ `agents/`: `planner`, `implementer`, `reviewer` (planner/reviewer chỉ đọc).
  - ✅ `commands/`: `/triage-issue`, `/plan-feature`, thêm `/implement-issue`, `/fix-pr`, `/review-pr`.
- ✅ Reusable workflows: `triage.yml`, `merge-gate.yml`, `release.yml`, thêm
  `implement.yml`, `review.yml`, `quality.yml`, `usage-report.yml`.
- ✅ CI của toolkit: `self-test.yml` (manifest, actionlint + shellcheck, caller template
  kiểm tra chéo với input của reusable workflow, bootstrap thử).
- 👤 Thử trên repo sandbox → [SETUP §D](SETUP.md#d-thử-nghiệm-trước-khi-dùng-thật-cuối-giai-đoạn-1)

## Giai đoạn 2 — Intake & triage
- ✅ Issue template có cấu trúc (Goal / Constraints / Acceptance criteria), feature + bug.
- ✅ Nhãn chuẩn ([`templates/.github/labels.json`](../templates/.github/labels.json)), `bootstrap.sh` tạo sẵn.
- ✅ `triage.yml`: chạy khi mở/sửa issue, khi có nhãn `needs-triage`, khi tác giả trả lời
  `awaiting-clarification`, và quét 6 giờ/lần. Tối đa `max-rounds` (3) vòng hỏi, đếm
  bằng marker ẩn → quá thì `needs-human`. Chấm điểm 0–5, gắn type/priority/risk/size.

## Giai đoạn 3 — GitHub Projects
- 👤 Tạo Project v2 + field `Priority`, `Size`; secret `PROJECT_TOKEN`.
- ✅ Issue `ready` được `gh project item-add` và set field qua `gh project item-edit`.

## Giai đoạn 4 — Build sub-agent
- ✅ Mỗi issue → branch `agent/issue-N`, runner ephemeral, `--max-turns`, `--allowedTools`
  giới hạn + `--disallowedTools` cho push/reset/rebase/checkout.
- ✅ Cài plugin trước khi gọi agent — qua input `plugin_marketplaces` / `plugins` của
  claude-code-action (tương đương `claude plugin marketplace add` + `claude plugin install`).
- ✅ Concurrency group theo issue/PR, không cancel run đang chạy.
- ✅ Circuit breaker: đếm lần fix trên PR; ≥ `max-fix-attempts` (3) → `needs-human`, dừng.
  🔀 Đếm cả lỗi CI lẫn review yêu cầu sửa, không chỉ CI.
- ✅ Tự khởi động sau triage khi `risk≠high` và `size≤M`; người có thể gắn `agent:implement`.

## Giai đoạn 5 — PR & CI
- ✅ PR tự tạo với `Closes #N`, nhãn `agent`; chưa xong thì mở dạng draft.
- ✅ `quality.yml`: lint → format → test → coverage (không giảm so với `develop`,
  baseline lưu làm artifact) → kiểm tiêu đề PR Conventional Commits.
- ✅ Security thay CodeQL: Semgrep CLI (chỉ finding mới), Gitleaks action, 👤 bật Dependabot alerts.
- ✅ `review.yml`: chạy song song với CI, comment inline, ghi commit status `agent/review`.

## Giai đoạn 6 — Merge gate
- ✅ Caller trigger `workflow_run: completed` của `CI` và `Agent Review`; kiểm mọi check
  run + commit status của head SHA qua API.
- ✅ Pass → `gh pr merge --squash --delete-branch --match-head-commit`.
  🔀 Dùng token GitHub App nếu có (merge bằng `GITHUB_TOKEN` không kích hoạt workflow sau
  merge); không có App thì vẫn dùng `GITHUB_TOKEN` như kế hoạch.
- ✅ Rollback: smoke test chạy ngay trong merge-gate sau khi merge (không chờ push event
  vì có thể không bắn), fail → PR revert + mở lại issue, `needs-human`.

## Giai đoạn 7 — Release
- 👤 Merge `develop` → `main` sau khi review.
- ✅ `release.yml`: release-please (version, CHANGELOG, tag), build + upload artifact.

## Giai đoạn 8 — Guardrail
- ✅ Transcript mỗi lần Claude chạy → artifact `transcript-*` (30 ngày).
- ✅ `timeout-minutes` cho mọi job (triage 10, build 45, review 15, CI 20, gate 10).
- ✅ `usage-report.yml`: issue tổng hợp phút Actions (theo workflow) + chi phí Claude
  (từ transcript), cảnh báo ở 80% ngân sách; mỗi job agent ghi chi phí vào Step Summary.

## Giai đoạn 9 — Rollout
- ✅ `scripts/bootstrap.sh <repo> --ref <tag>` chép caller + template, tạo nhãn, `develop`.
- ✅ Ghim theo tag: `toolkit-release.yml` tạo tag `vX.Y.Z` + tag di động `vX`.
