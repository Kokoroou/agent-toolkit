# agent-toolkit

Pipeline agent-driven **issue → triage → build → PR → CI/review → auto-merge → release**
cho repo GitHub Free (kể cả private), chạy bằng Claude Code trong GitHub Actions.
Dùng chung cho mọi dự án: repo dự án chỉ giữ vài file YAML mỏng gọi vào đây.

```
issue ─▶ triage ─▶ planner ─▶ implementer ─▶ PR ─▶ CI + reviewer ─▶ merge gate ─▶ develop ─▶ (bạn) ─▶ main ─▶ release
            │                                          │                 │
            └─ hỏi lại ≤3 vòng                         └─ fix ≤3 lần ────┴─ fail → needs-human / revert
```

## Thành phần

| Đường dẫn | Là gì |
|---|---|
| [`plugins/pipeline/`](plugins/pipeline) | Plugin Claude Code: sub-agent `planner` / `implementer` / `reviewer`, lệnh `/triage-issue` `/plan-feature` `/implement-issue` `/fix-pr` `/review-pr`, skill `pipeline-conventions` |
| [`.github/workflows/triage.yml`](.github/workflows/triage.yml) | Làm rõ, chấm điểm, gắn nhãn issue; thêm vào GitHub Projects |
| [`.github/workflows/implement.yml`](.github/workflows/implement.yml) | Build agent: branch `agent/issue-N`, commit, PR; chế độ fix + circuit breaker |
| [`.github/workflows/review.yml`](.github/workflows/review.yml) | Review PR, comment inline, commit status `agent/review` |
| [`.github/workflows/quality.yml`](.github/workflows/quality.yml) | CI: lint → format → test → coverage không giảm, tiêu đề PR, Semgrep + Gitleaks |
| [`.github/workflows/merge-gate.yml`](.github/workflows/merge-gate.yml) | Cổng merge tự viết (thay branch protection), smoke test + revert |
| [`.github/workflows/release.yml`](.github/workflows/release.yml) | release-please + build + upload artifact |
| [`.github/workflows/usage-report.yml`](.github/workflows/usage-report.yml) | Báo cáo phút Actions + chi phí Claude |
| [`workflows/ci-doctor.md`](workflows/ci-doctor.md) | Workflow gh-aw: lỗi CI trên develop/main → issue |
| [`templates/`](templates) | File chép vào repo dự án (caller workflow, issue template, nhãn, `CLAUDE.md`) |
| [`scripts/bootstrap.sh`](scripts/bootstrap.sh) | Cài pipeline vào một repo dự án |

## Bắt đầu nhanh

Lần đầu dùng? Đọc [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) rồi
[docs/ADD-TO-PROJECT.md](docs/ADD-TO-PROJECT.md). Tóm tắt:

```bash
git clone https://github.com/kokoroou/agent-toolkit /tmp/agent-toolkit
/tmp/agent-toolkit/scripts/bootstrap.sh ~/code/my-project --ref v0
# sửa các khối "edit for your stack", thêm secret ANTHROPIC_API_KEY (+ GitHub App), commit
```

Một workflow trong repo dự án chỉ cần:

```yaml
jobs:
  triage:
    uses: kokoroou/agent-toolkit/.github/workflows/triage.yml@v0
    with:
      issue-number: ${{ github.event.issue.number }}
    secrets: inherit
```

Dùng plugin khi làm việc tay:

```bash
claude plugin marketplace add kokoroou/agent-toolkit
claude plugin install pipeline@agent-toolkit
# trong Claude Code: /pipeline:plan-feature 42
```

## Tài liệu

- [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) — lần đầu dùng: công cụ, thông tin đăng nhập Claude, GitHub App, thử trên repo sandbox
- [docs/ADD-TO-PROJECT.md](docs/ADD-TO-PROJECT.md) — thêm pipeline vào một dự án: bootstrap, sửa theo stack, secret, settings, ghim phiên bản, xử lý sự cố
- [docs/MAINTAINING.md](docs/MAINTAINING.md) — bảo trì toolkit: phát triển, kiểm thử, phát hành
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — luồng chi tiết, nguyên tắc an toàn, các "bẫy" GitHub đã xử lý
- [docs/PLAN.md](docs/PLAN.md) — kế hoạch thi công 9 giai đoạn và trạng thái từng mục

## Phát triển toolkit

```bash
scripts/lint.sh   # cần claude, actionlint, shellcheck, jq
```

Commit theo Conventional Commits; `toolkit-release.yml` phát hành `vX.Y.Z` và dời tag `vX`.
Chi tiết: [docs/MAINTAINING.md](docs/MAINTAINING.md).
