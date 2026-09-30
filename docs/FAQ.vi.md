# Use case và câu hỏi thường gặp

[English](FAQ.md) · **Tiếng Việt**

Tra nhanh "muốn làm X thì làm sao" và "vì sao lại Y". Mỗi mục trả lời ngắn rồi dẫn tới tài
liệu chi tiết. Gặp vấn đề mới thì thêm một mục theo [mẫu cuối trang](#cách-bổ-sung-mục-mới).

- [Use case thường gặp](#use-case-thường-gặp)
  - Cài đặt: [UC-1](#uc-1-cài-pipeline-vào-một-dự-án) · [UC-2](#uc-2-nâng-cấp-toolkit)
  - Giao việc và thi công: [UC-3](#uc-3-giao-một-việc-cho-agent) · [UC-4](#uc-4-làm-dần-backlog) · [UC-5](#uc-5-bật-build-tự-động-trên-github-actions)
  - Khi mọi thứ thay đổi: [UC-6](#uc-6-đổi-yêu-cầu-giữa-chừng) · [UC-7](#uc-7-huỷ-một-việc) · [UC-8](#uc-8-chặn-một-pr-không-cho-merge)
  - Khi agent bị kẹt: [UC-9](#uc-9-sửa-pr-agent-bị-đỏ) · [UC-10](#uc-10-tiếp-quản-sau-needs-human)
  - Khác: [UC-11](#uc-11-cho-agent-review-pr-của-người) · [UC-12](#uc-12-chạy-phiên-agent-trên-máy-có-sandbox) · [UC-13](#uc-13-chạy-phiên-agent-trên-claude-cloud) · [UC-14](#uc-14-phát-hành-một-phiên-bản) · [UC-15](#uc-15-theo-dõi-chi-phí)
- [Câu hỏi thường gặp](#câu-hỏi-thường-gặp)
  - [Chung](#chung) · [Cài đặt và cấu hình](#cài-đặt-và-cấu-hình) · [Vận hành](#vận-hành) ·
    [Sự cố](#sự-cố) · [Bảo mật và chi phí](#bảo-mật-và-chi-phí)
- [Cách bổ sung mục mới](#cách-bổ-sung-mục-mới)

---

## Use case thường gặp

### UC-1. Cài pipeline vào một dự án

1. Làm một lần cho mọi dự án: lấy token Claude và tạo GitHub App →
   [GETTING-STARTED §4–5](GETTING-STARTED.vi.md#4-chuẩn-bị-thông-tin-đăng-nhập-claude).
2. Trong thư mục clone của dự án (đang ở default branch):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh | bash
   ```

3. Kiểm tra lệnh lint/test/coverage script đã điền ([ADD-TO-PROJECT §3](ADD-TO-PROJECT.vi.md#3-sửa-workflow-cho-stack-của-dự-án)),
   điền `CLAUDE.md` ([§4](ADD-TO-PROJECT.vi.md#4-viết-claudemd)), rồi mở một issue nhỏ để
   thử cả vòng ([§8](ADD-TO-PROJECT.vi.md#8-commit-và-kiểm-tra)).

Repo đã có sẵn `ci.yml` hoặc issue template: script giữ file của bạn, chỉ báo lại →
[§2.3](ADD-TO-PROJECT.vi.md#23-repo-đã-có-sẵn-file).

### UC-2. Nâng cấp toolkit

- Logic pipeline (reusable workflow, plugin) tự cập nhật qua tag `@v0`, không cần làm gì.
- File đã chép vào dự án: chạy `upgrade.sh` (xem trước bằng `--dry-run`), đọc bảng kết
  quả, giải quyết file có `!`, rồi tự commit →
  [ADD-TO-PROJECT §10.2](ADD-TO-PROJECT.vi.md#102-lệnh-nâng-cấp).

### UC-3. Giao một việc cho agent

1. Mở issue từ template (Goal / Constraints / Acceptance criteria). Tiêu chí nghiệm thu càng
   cụ thể, agent hỏi lại càng ít.
2. Triage gắn nhãn; nếu thiếu thông tin thì hỏi lại (tối đa 5 vòng) — trả lời bằng comment.
3. Khi issue có `ready-for-plan`, trong Claude Code trên dự án (máy bạn hoặc web):
   `/pipeline:build N` (hoặc nói "thi công issue N"). Xác nhận khi được hỏi push.
4. CI + reviewer chạy trên PR; merge gate tự squash-merge vào `main` (`develop` với gitlab-flow) khi xanh.

### UC-4. Làm dần backlog

`/pipeline:build` không tham số: gom issue sẵn sàng và PR agent bị đỏ, xếp hạng (PR đỏ
trước, rồi P0→P3, bug, size nhỏ, cũ hơn), đề xuất thứ tự và thi công lần lượt những việc
bạn duyệt → [GETTING-STARTED §7](GETTING-STARTED.vi.md#7-dùng-plugin-khi-làm-việc-tay-tuỳ-chọn).

### UC-5. Bật build tự động trên GitHub Actions

```bash
gh variable set AGENT_AUTO_BUILD --body true
```

Issue có `risk` khác `high` và `size` ≤ `auto-implement-max-size` (mặc định M) sẽ được
build trên Actions ngay sau triage; PR đỏ được gửi lại agent sửa (tối đa 3 lần). Chỉ muốn
build một issue trên Actions: gắn nhãn `agent:implement` →
[ADD-TO-PROJECT §3.4](ADD-TO-PROJECT.vi.md#34-các-tuỳ-chỉnh-khác-thường-dùng).

### UC-6. Đổi yêu cầu giữa chừng

Sửa **nội dung issue** (không phải thêm comment). Triage chạy lại, vòng hỏi đếm lại từ 0.
PR agent đang mở cho issue đó bị gắn `needs-human`: đóng PR, xoá branch, build lại khi
issue về `ready-for-plan` → [ARCHITECTURE](ARCHITECTURE.vi.md#đổi-yêu-cầu-và-huỷ).

### UC-7. Huỷ một việc

Đóng issue (và PR nếu có). Build đang chạy sẽ không push, không mở PR; merge gate không
merge PR có issue đã đóng.

### UC-8. Chặn một PR không cho merge

Gắn `do-not-merge` hoặc `risk:high` vào PR. Merge gate trả về `blocked`.

### UC-9. Sửa PR agent bị đỏ

Merge gate comment sẵn lệnh trên PR: chạy `/pipeline:build pr P` trong Claude Code. Với
`AGENT_AUTO_BUILD=true`, việc này tự chạy trên Actions tối đa 3 lần rồi dừng ở
`needs-human` (circuit breaker).

### UC-10. Tiếp quản sau `needs-human`

1. Tìm lý do: comment của bot, Step Summary của run, hoặc artifact `transcript-*`.
2. Issue: sửa issue cho rõ, bỏ nhãn `needs-human`, rồi `/pipeline:build N`.
3. PR: tự sửa và push (hoặc `/pipeline:build pr P`), bỏ nhãn; merge gate chạy lại khi CI
   xong.

### UC-11. Cho agent review PR của người

Gắn nhãn `agent` vào PR. **Lưu ý:** PR đó sẽ đủ điều kiện để merge gate tự merge khi xanh;
gắn thêm `do-not-merge` nếu chỉ muốn nhận review.

### UC-12. Chạy phiên agent trên máy, có sandbox

`scripts/agent-session.sh run`: giải mã `.env.age`, kéo file từ storage, chạy Claude trong
sandbox (không push được, mạng chỉ tới GitHub + registry). Khi thoát, `publish` cho bạn
xem commit rồi mới push và mở PR → [AGENT-SESSION §4](AGENT-SESSION.vi.md#4-phiên-trên-máy-bạn).

### UC-13. Chạy phiên agent trên Claude cloud

Tạo key riêng bằng `scripts/agent-session.sh cloud-key claude-cloud`, đặt `AGE_SECRET_KEY`
trong environment, **không** đưa credential storage nào vào →
[AGENT-SESSION §5](AGENT-SESSION.vi.md#5-phiên-trên-claude-cloud).

### UC-14. Phát hành một phiên bản

Với gitlab-flow, trước tiên merge PR promotion `develop` → `main` mà Branch Sync luôn giữ
mở (bằng merge commit); với github-flow (mặc định) thay đổi đã nằm sẵn trên `main`.
release-please mở release PR; merge PR đó → tag,
CHANGELOG, GitHub Release → [ADD-TO-PROJECT §9.4](ADD-TO-PROJECT.vi.md#94-release).

### UC-15. Theo dõi chi phí

Issue `pipeline-usage` (từ *Agent Usage Report*, hằng tuần hoặc chạy tay) tổng hợp phút
Actions và chi phí Claude; mỗi run cũng ghi chi phí vào Step Summary. Đặt ngưỡng bằng
`minutes-budget`, `cost-budget-usd` trong `agent-usage-report.yml`.

---

## Câu hỏi thường gặp

### Chung

#### Có cần GitHub trả phí không?

Không. Chạy được trên GitHub Free, kể cả repo private. Merge gate thay cho branch
protection (Free + private không có).

#### Dùng API key hay OAuth token của Claude?

Cái nào cũng được. `claude setup-token` cho OAuth token nếu bạn có gói Pro/Max (bị giới hạn
theo quota gói); API key tính tiền theo token, nên đặt spend limit trong Console →
[GETTING-STARTED §4](GETTING-STARTED.vi.md#4-chuẩn-bị-thông-tin-đăng-nhập-claude).

#### Vì sao triage xong mà agent không tự build?

Đó là mặc định: bạn quyết định khi nào build (`/pipeline:build N`), để agent chạy với đầy
đủ harness của bạn và bạn xem được nó làm. Muốn tự động: [UC-5](#uc-5-bật-build-tự-động-trên-github-actions).

#### Issue `size:L`/`XL` hoặc `risk:high` thì sao?

Không bao giờ tự build hay tự merge. Bạn vẫn build tay được bằng `/pipeline:build N`; PR
`risk:high` phải merge tay.

#### `needs-human` nghĩa là gì?

"Đến lượt người": mọi đường lỗi (hết vòng hỏi, circuit breaker, conflict, smoke test
fail…) đều dừng ở nhãn này và mọi agent bỏ qua issue/PR mang nó. Xem [UC-10](#uc-10-tiếp-quản-sau-needs-human).

#### Stack của tôi không phải Node/Python/Go?

Cài với `--stack none`: mọi lệnh để trống, bạn tự điền trong các khối `edit for your stack`
→ [ADD-TO-PROJECT §3](ADD-TO-PROJECT.vi.md#3-sửa-workflow-cho-stack-của-dự-án).

### Cài đặt và cấu hình

#### GitHub App có bắt buộc không?

Không, nhưng rất nên có. Sự kiện tạo bởi `GITHUB_TOKEN` không kích hoạt workflow khác, nên
không có App thì toolkit phải dispatch CI riêng và check không hiện trên PR →
[ARCHITECTURE](ARCHITECTURE.vi.md#những-bẫy-của-github-đã-được-xử-lý).

#### Vì sao nên để `develop` làm default branch?

Chỉ áp dụng cho gitlab-flow; với github-flow `main` là default branch.
`workflow_run`, `schedule` và `workflow_dispatch` chỉ đọc workflow trên default branch.
Để `main` làm default cũng được nhưng phải nhớ đồng bộ workflow sang `main` →
[ADD-TO-PROJECT §7](ADD-TO-PROJECT.vi.md#7-chọn-default-branch).

#### Tôi sửa caller workflow, nâng cấp có mất không?

Không, `upgrade.sh` merge 3 chiều dựa trên `.github/agent-toolkit.lock`. Để tránh conflict,
chỉ sửa giá trị trong các khối `edit for your stack` và `with:`; bước thêm thì viết workflow
riêng → [ADD-TO-PROJECT §10.3](ADD-TO-PROJECT.vi.md#103-cách-script-giữ-lại-chỉnh-sửa-của-bạn).

#### `CLAUDE.md` có bị ghi đè khi nâng cấp không?

Không. Nó chỉ được tạo một lần và thuộc về dự án.

#### Chạy lại lệnh cài có an toàn không?

Có. File đã tồn tại được giữ (trừ khi `--force`), nhãn được cập nhật, secret đã có chỉ bị
thay khi bạn đồng ý.

#### Dùng trên Windows được không?

Lệnh cài chạy bằng PowerShell (`install.ps1`). Riêng sandbox của `agent-session.sh run`
cần WSL2, vì sandbox Claude Code không chạy trên Windows gốc.

### Vận hành

#### Triage không phản hồi khi tôi trả lời câu hỏi?

Phải comment bằng tài khoản người (comment của bot bị bỏ qua), và issue phải còn
`awaiting-clarification`. Nếu không, gắn lại `needs-triage`.

#### PR từ phiên cloud không nằm trên branch `agent/issue-N`?

Bình thường: proxy GitHub của cloud chỉ cho push lên branch của phiên. Review và merge gate
dựa vào nhãn `agent` và `Closes #N`, không dựa vào tên branch.

#### Issue không tự đóng sau khi merge?

`Closes #N` chỉ có tác dụng khi merge vào default branch, nên merge gate tự đóng issue. Nếu
vẫn mở: xem log merge gate, kiểm tra PR có `Closes #N`, rồi đóng tay.

#### Xem agent đã làm gì ở đâu?

*Actions → run → Summary* (quyết định, chi phí, số lượt) và artifact `transcript-*` (toàn bộ
hội thoại của Claude) → [GETTING-STARTED §8.3](GETTING-STARTED.vi.md#83-xem-agent-đã-làm-gì).

### Sự cố

Bảng đầy đủ: [ADD-TO-PROJECT §12](ADD-TO-PROJECT.vi.md#12-xử-lý-sự-cố). Các lỗi hay gặp nhất:

| Triệu chứng | Kiểm tra trước |
|---|---|
| Mở issue mà không workflow nào chạy | Caller có nằm trên default branch không; Actions có bật không |
| `Agent Merge Gate` không chạy | File ở default branch; workflow CI có tên đúng `CI` |
| `GitHub Actions is not permitted to create or approve pull requests` | Bật quyền đó trong *Settings → Actions → General* |
| Bước *Mint GitHub App token* lỗi | App đã cài vào repo chưa; App ID; private key đủ dòng BEGIN/END |
| Lỗi xác thực Claude / `401` | Tạo lại token (`claude setup-token`) và đặt lại secret |
| Agent bị từ chối lệnh | Thêm lệnh vào `extra-allowed-tools` ở cả `agent-implement.yml` và job `fix` |
| `coverage-command must print the percentage on its last line` | Dòng cuối stdout phải là số; đẩy output khác sang `>&2` |

### Bảo mật và chi phí

#### Agent có thể làm lộ secret hoặc push code bậy không?

Agent trên Actions không bao giờ giữ token có quyền ghi: commit rời job dưới dạng
`git bundle` và được một job khác kiểm tra trước khi push; không có WebFetch/WebSearch; issue
từ người ngoài không tự khởi động build → [SECURITY](SECURITY.vi.md#mô-hình-lethal-trifecta).
Ở phiên trên máy, agent đọc được `.env` (test cần), nên chỉ để credential dev/test ở đó.

#### Một issue tốn bao nhiêu?

Thường vài chục phút Actions (triage 1–3 phút/vòng, build 5–45 phút, review 2–15 phút) cộng
chi phí Claude ghi trong Step Summary. `timeout-minutes`/`max-turns` chặn run chạy quá lâu →
[GETTING-STARTED §9](GETTING-STARTED.vi.md#9-chi-phí-và-giới-hạn).

---

## Cách bổ sung mục mới

- **Use case** ("muốn làm X thì làm sao"): thêm `### UC-<số tiếp theo>. <việc cần làm>`
  vào nhóm phù hợp và vào mục lục đầu trang.
- **Câu hỏi** ("vì sao Y", "có được Z không"): thêm `#### <câu hỏi>?` vào nhóm phù hợp. Lỗi
  có triệu chứng rõ thì thêm một dòng vào bảng [Sự cố](#sự-cố) (và vào
  [ADD-TO-PROJECT §12](ADD-TO-PROJECT.vi.md#12-xử-lý-sự-cố) nếu đáng ghi lâu dài).
- Trả lời ngắn (2–5 dòng), rồi link tới mục chi tiết thay vì chép lại.
- Không đổi số UC đã có (có thể đang được link tới); mục bỏ đi thì ghi "đã bỏ".
- Cập nhật cả [FAQ.md](FAQ.md) bản tiếng Anh, cùng số UC.

Mẫu:

```markdown
### UC-16. <Việc cần làm>

<1–3 bước hoặc lệnh> → [<tài liệu> §<mục>](<file>.vi.md#<anchor>).

#### <Câu hỏi>?

<Trả lời ngắn: làm gì / vì sao.> → [<tài liệu>](<file>.vi.md#<anchor>).
```
