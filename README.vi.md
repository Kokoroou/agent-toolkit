# agent-toolkit

[English](README.md) · **Tiếng Việt**

**Cho Claude Code tự xử lý issue GitHub: hỏi lại cho rõ, viết code + test, mở PR, review
và merge — bạn chỉ việc mở issue và duyệt bản phát hành.**

- Chạy trên **GitHub Free**, kể cả repo private, bằng GitHub Actions.
- Dùng chung cho mọi dự án: repo dự án chỉ giữ vài file YAML mỏng gọi vào toolkit này,
  nên nâng cấp một chỗ là mọi dự án được cập nhật.
- An toàn mặc định: agent không cầm token ghi, việc rủi ro cao không bao giờ tự merge, mọi
  lỗi đều dừng lại chờ người (nhãn `needs-human`).

```
issue ─▶ triage ─▶ planner ─▶ implementer ─▶ PR ─▶ CI + reviewer ─▶ merge gate ─▶ develop ─▶ (bạn) ─▶ main ─▶ release
            │                                          │                 │
            └─ hỏi lại ≤5 vòng                         └─ fix ≤3 lần ────┴─ fail → needs-human / revert
```

## Bắt đầu trong 3 bước

1. **Chuẩn bị một lần** (~15 phút): token Claude + GitHub App →
   [GETTING-STARTED §4–5](docs/GETTING-STARTED.vi.md#4-chuẩn-bị-thông-tin-đăng-nhập-claude).
2. **Cài vào dự án** — đứng trong thư mục clone của repo dự án và chạy:

   ```bash
   # Linux / macOS / WSL
   curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh | bash
   ```

   ```powershell
   # Windows
   irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1 | iex
   ```

   Script tự nhận diện stack, chép workflow, tạo nhãn + branch `develop`, đặt secret, bật
   settings và commit; chỉ hỏi những gì còn thiếu.
3. **Điền `CLAUDE.md` rồi mở một issue nhỏ** để xem pipeline chạy hết vòng →
   [ADD-TO-PROJECT §8](docs/ADD-TO-PROJECT.vi.md#8-commit-và-kiểm-tra).

## Đọc gì tiếp theo

| Bạn muốn | Đọc | Thời gian |
|---|---|---|
| Hiểu pipeline làm gì, chuẩn bị tài khoản, thử trên sandbox | [GETTING-STARTED.md](docs/GETTING-STARTED.vi.md) | 10 phút đọc |
| Cài vào một dự án, sửa theo stack, nâng cấp, xử lý sự cố | [ADD-TO-PROJECT.md](docs/ADD-TO-PROJECT.vi.md) | tra cứu theo mục |
| Hiểu thiết kế, luồng chi tiết, các "bẫy" GitHub | [ARCHITECTURE.md](docs/ARCHITECTURE.vi.md) | 5 phút |
| Đánh giá rủi ro bảo mật | [SECURITY.md](docs/SECURITY.vi.md) | 5 phút |
| Sửa / phát hành chính toolkit | [MAINTAINING.md](docs/MAINTAINING.vi.md) | người bảo trì |
| Lịch sử thi công và trạng thái từng hạng mục | [PLAN.md](docs/PLAN.vi.md) | tham khảo |

## Thuật ngữ

| Từ | Nghĩa |
|---|---|
| **Triage** | Agent đọc issue, hỏi lại nếu chưa rõ, rồi gắn nhãn loại / ưu tiên / rủi ro / kích cỡ |
| **Build agent** | Agent lập kế hoạch (*planner*) rồi viết code + test (*implementer*) trên branch `agent/issue-N` |
| **Reviewer** | Agent review PR, comment inline, ghi kết quả vào status `agent/review` |
| **Merge gate** | Workflow thay cho branch protection: PR xanh → squash-merge; PR đỏ → gửi agent sửa |
| **Circuit breaker** | Sửa quá 3 lần vẫn đỏ → dừng, gắn `needs-human` |
| **`needs-human`** | Nhãn "đến lượt người": mọi agent bỏ qua issue/PR mang nhãn này |
| **Caller workflow** | File YAML mỏng trong repo dự án, gọi *reusable workflow* của toolkit bằng `uses: …@v0` |
| **`@v0`** | Tag di động trỏ tới bản 0.x mới nhất; dự án tự nhận bản vá mà không phải sửa gì |

## Nâng cấp

Logic pipeline tự cập nhật theo tag `@v0`. File đã chép vào dự án thì nâng cấp bằng lệnh
sau (chỉnh sửa của bạn được giữ nhờ 3-way merge; chi tiết:
[ADD-TO-PROJECT §10](docs/ADD-TO-PROJECT.vi.md#10-ghim-và-nâng-cấp-phiên-bản-toolkit)):

```bash
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/upgrade.sh | bash -s -- --dry-run
```

## Dùng plugin khi làm việc tay

Các agent của pipeline cũng dùng được trong Claude Code trên máy bạn, không cần workflow
hay secret:

```bash
claude plugin marketplace add kokoroou/agent-toolkit
claude plugin install pipeline@agent-toolkit
# trong Claude Code: /pipeline:plan-feature 42
```

Danh sách lệnh: [GETTING-STARTED §7](docs/GETTING-STARTED.vi.md#7-dùng-plugin-khi-làm-việc-tay-tuỳ-chọn).

## Trong repo có gì

<details>
<summary>Bảng thành phần (dành cho người muốn đọc mã)</summary>

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
| [`scripts/install.sh`](scripts/install.sh), [`install.ps1`](scripts/install.ps1) | Cài pipeline vào một repo dự án bằng một lệnh (file, secret, settings, commit) |
| [`scripts/upgrade.sh`](scripts/upgrade.sh) | Nâng cấp file đã chép trong repo dự án lên bản toolkit mới, giữ chỉnh sửa của bạn bằng 3-way merge |
| [`scripts/bootstrap.sh`](scripts/bootstrap.sh) | Phần chép file + nhãn + `develop` mà `install.sh` dùng |

Một caller workflow trong repo dự án trông như sau (bản đầy đủ ở
[`templates/.github/workflows/`](templates/.github/workflows)):

```yaml
jobs:
  triage:
    uses: kokoroou/agent-toolkit/.github/workflows/triage.yml@v0
    with:
      issue-number: ${{ github.event.issue.number }}
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
      claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

</details>

## Phát triển toolkit

```bash
scripts/lint.sh   # cần claude, actionlint, shellcheck, jq
```

Commit theo Conventional Commits; `toolkit-release.yml` phát hành `vX.Y.Z` và dời tag `vX`.
Chi tiết: [docs/MAINTAINING.md](docs/MAINTAINING.vi.md).
