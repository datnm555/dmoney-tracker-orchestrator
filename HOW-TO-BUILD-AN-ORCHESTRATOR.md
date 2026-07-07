# Cách dựng một "Orchestrator" — mỗi service = 1 skill, AI hiểu scope toàn hệ thống

> Tài liệu tổng hợp từ chính cấu trúc repo `orchestrator` này. Mục tiêu: hướng dẫn
> dựng một **central orchestrator** để một AI coding agent (**Claude Code, GitHub
> Copilot, Codex, Cursor…**) hiểu được **toàn bộ một hệ thống nhiều repo / nhiều
> microservice**, trong đó **mỗi service / domain được đóng gói thành 1 "skill"** mà
> agent tự nạp đúng lúc.
>
> Tài liệu này **tool-agnostic**: phần §1–§10 mô tả mô hình chung; **§11 ánh xạ cụ thể
> sang GitHub Copilot / Codex** để các tool đó cũng đọc-hiểu-và-tự dựng được.

---

## 0. Orchestrator là gì (và KHÔNG là gì)

**Orchestrator = một repo trung tâm chỉ chứa "bộ não vận hành" cho AI**, không chứa
code sản phẩm.

| Chứa | KHÔNG chứa |
|---|---|
| Skill definitions (1 skill / service / domain) | Code sản phẩm (nằm ở repo gốc) |
| `CLAUDE.md` — luật + cách làm việc | Logic nghiệp vụ |
| Slash commands, hooks, agent config | Build artifacts |
| Bản đồ routing (topic → skill, thư mục → skill) | |
| Knowledge base offline (Jira/Confluence, docs) | |

Các repo thật được **clone vào làm "sibling" (read-only reference)** qua `make
clone-all`. Code thật vẫn sửa ở repo gốc; orchestrator chỉ *trỏ tới* code, không *giữ* code.

> Ở Vault22 hiện tại: **79 skills**, **21 repos** (18 ở org `22sevengithub` + 3 ở
> `SCV-Autumn`), 0 dòng code sản phẩm trong orchestrator.

---

## 1. Triết lý cốt lõi (4 nguyên tắc)

1. **One skill per service/domain.** Mỗi microservice (hoặc một domain xuyên repo)
   = đúng 1 skill. Skill là "hồ sơ vận hành" của service đó: kiến trúc, lệnh build/run,
   pattern code, cạm bẫy, file tham chiếu.

2. **Progressive disclosure (tiết lộ dần).** Context của AI là tài nguyên khan hiếm.
   → `CLAUDE.md` phải **mỏng** (nạp vào *mọi* session). Chi tiết đẩy xuống skill, và
   skill chỉ nạp **khi cần**. Bảng routing dài cũng tách ra file riêng
   (`agent_docs/skill-routing.md`), *được tham chiếu chứ không auto-load*.

3. **Trigger 3 chiều.** Một skill được kích hoạt bằng: **(a)** từ khoá/chủ đề,
   **(b)** thư mục đang làm việc, **(c)** gõ tay `/<skill-name>`. (Chi tiết ở §4.)

4. **Skill tự mô tả.** Mỗi skill có frontmatter `description` chứa luôn các "trigger"
   — agent đọc description để tự quyết định có nạp skill hay không. Routing table chỉ
   là lớp tăng cường cho việc match tự động.

5. **Một nguồn sự thật, nhiều lớp tương thích (tool-agnostic).** Nội dung skill là
   **nguồn duy nhất** (`.claude/skills/`); mỗi tool (Copilot, Codex, Cursor) chỉ thêm
   một **lớp tương thích mỏng** trỏ về nguồn đó — KHÔNG copy nội dung khác nhau cho mỗi
   tool. `AGENTS.md` là xương sống chung mọi agent đọc được. (Chi tiết §11.)

---

## 2. Bản đồ thư mục orchestrator

```
orchestrator/
├── CLAUDE.md                      # Luật + cách làm việc cho Claude Code (nạp MỌI session — phải mỏng)
├── AGENTS.md                      # ★ Luật chung mọi agent đọc (Copilot/Codex/Cursor) — xương sống đa-tool
├── .agents/skills -> .claude/skills   # Symlink: Codex thấy đúng nguồn skill
├── .github/                       # (tuỳ chọn) Lớp tương thích GitHub Copilot — xem §11
│   ├── copilot-instructions.md    #   = CLAUDE.md (luật global cho Copilot)
│   ├── instructions/*.instructions.md  #   = per-service skill (frontmatter applyTo)
│   └── prompts/*.prompt.md         #   = slash commands
├── README.md                      # Onboarding cho người mới (30 phút đầu)
├── Makefile                       # clone-all / pull-all / status / branches ...
├── agent_docs/
│   ├── skill-routing.md           # Bảng routing đầy đủ (tham chiếu, không auto-load)
│   └── local-env-setup.md         # Biến môi trường, secrets local
├── .claude/
│   ├── skills/                    # ★ 1 thư mục = 1 skill
│   │   ├── vault22-backend/
│   │   │   ├── SKILL.md           # Frontmatter + nội dung chính
│   │   │   └── references/        # Tài liệu sâu, nạp khi cần (progressive disclosure)
│   │   │       ├── architecture.md
│   │   │       ├── api-patterns.md
│   │   │       └── testing-guide.md
│   │   ├── core-microservices/    # Gom jill/jack/steph/NAPI vào 1 skill
│   │   ├── vault22-platform/      # ★ Skill "scope toàn hệ thống" (xem §5)
│   │   └── ... (79 skills)
│   ├── commands/                  # Slash command (/create-pr, /cross-repo-search, ...)
│   ├── hooks/                     # Hook tự động (session start, pre/post tool-use)
│   ├── settings.json              # Cấu hình harness + hooks
│   └── workflows/                 # Workflow đa-agent (tuỳ chọn)
├── vault/                         # Knowledge base offline (Jira/Confluence → Obsidian)
└── core/  global-website/  ...    # 21 repo thật, clone làm sibling (read-only ref)
```

**Quy luật vàng về vị trí code:** mọi thay đổi code/commit/PR làm ở **repo thật**, KHÔNG
phải bản clone reference trong orchestrator.

---

## 3. Anatomy của 1 skill (mỗi service một file SKILL.md)

Đây là phần quan trọng nhất. Một skill tối thiểu = 1 file `SKILL.md`:

```markdown
---
name: vault22-backend
description: Use this skill when working with the Vault22 Core backend repository
  (core/). This includes building, testing, running Briteblue.Api/.Service .NET 8.0,
  the Manager/Repository pattern, NUnit tests, PRs. Triggers include "core repository",
  "Briteblue", "backend API", "customer manager", "MongoDB repository", or working in
  the core/ directory.
---

# Vault22 Backend (Core) Skill

Mô tả 1 dòng service làm gì.

## Overview          ← bảng: location, framework, solution, DB, port
## Quick Commands    ← lệnh build / run / test copy-paste được ngay
## Solution Structure← layer/projects
## Reference Files   ← trỏ sang references/*.md (đọc khi cần)
## Key Rules         ← pattern bắt buộc + cạm bẫy ("DO NOT TOUCH PushManager.cs")
## API Authentication← cách gọi/đăng nhập
## Related Skills    ← link sang skill liên quan
```

### `description` (frontmatter) là "bộ kích hoạt"
- Viết theo công thức: **"Use this skill when ... Triggers include '<từ khoá>', '<từ
  khoá>', or working in the `<dir>/` directory."**
- Liệt kê **đúng các từ người dùng hay nói** + **đường dẫn thư mục** → agent tự match.
- Càng cụ thể, match càng chuẩn, càng ít nạp nhầm.

### Nội dung skill nên có (checklist cho microservice)
- [ ] **Overview table** — vị trí, framework/version, solution/entry-point, DB, port
- [ ] **Quick commands** — build / run / test (copy-paste chạy được)
- [ ] **Kiến trúc & pattern** — Manager/Repository, state machine, naming (vd `…Async`)
- [ ] **Ranh giới & cạm bẫy** — file cấm sửa, sharding rule, auth rule
- [ ] **Cách test** — convention đặt tên test, lệnh chạy filter
- [ ] **Related skills** — service này phụ thuộc / gọi service nào
- [ ] **references/** — tài liệu dài (architecture, deployment) tách ra, nạp khi cần

### Khi nào gộp nhiều service vào 1 skill?
Khi chúng cùng họ và thường được nói tới chung. Ví dụ `core-microservices` gom
**4 service** (jill = account refresh, jack = KYC/loans/2FA, steph = SignalR,
NAPI = native API) vào 1 skill có bảng so sánh. Service lớn/độc lập → skill riêng
(vd `vault22-backend`, `saasport`, `categorisation-service`).

### Progressive disclosure trong skill
`SKILL.md` giữ phần "đủ để bắt đầu". Phần sâu (vd `architecture.md`, `testing-guide.md`)
để trong `references/` và **chỉ trỏ tới** — agent đọc khi thực sự cần. Skill rất lớn
có thể chia `sections/` (vd skill `mongodb`).

---

## 4. Lớp routing — agent biết nạp skill nào, khi nào

Có 3 cách trigger, khai báo ở `CLAUDE.md` (mỏng) + `agent_docs/skill-routing.md` (đầy đủ):

**(a) Theo chủ đề / từ khoá** — bảng `User says... → Use Skill → Examples`:
```
| MongoDB, Atlas, slow queries, tier downgrade | /mongodb  | "query customer collection", "can we go M20?" |
| VLT22-, work on ticket, fix ticket           | /ticket-worker | "work on VLT22-9700" |
```

**(b) Theo thư mục đang làm việc** — `Working Directory → Use Skill`:
```
| core/                         | vault22-backend     | Main backend API |
| core.jill/ core.jack/ ...     | core-microservices  | Supporting microservices |
| global-website/               | vault22-website     | Next.js frontend |
| global-website/components/budget/ | vault22-budget  | (skill con, cụ thể hơn) |
```
→ Lưu ý: map có thể **lồng nhau** — thư mục con cụ thể hơn ăn skill chuyên biệt hơn.

**(c) Gõ tay** — người dùng/agent gõ `/<skill-name>` để ép nạp bất kể bảng.

**Luật bắt buộc:** *LUÔN nạp skill khớp TRƯỚC khi trả lời* — không trả lời chủ đề đã có
skill bằng "kiến thức chung".

`CLAUDE.md` chỉ giữ con trỏ tới `skill-routing.md` + vài luật sống còn → mọi session,
mọi subagent đều nhẹ.

---

## 5. Hiểu scope TOÀN hệ thống — skill "platform" (bird's-eye view)

Đây là câu trả lời cho vế "hiểu scope của toàn bộ hệ thống (gồm microservice)".
Tạo **1 skill tổng** (ở đây là `vault22-platform`) đóng vai bản đồ toàn cảnh:

`vault22-platform/SKILL.md` chứa:
- **Sơ đồ kiến trúc** toàn platform (ascii/diagram) — các tầng giao tiếp với nhau ra sao.
- **Repository Classification** — phân nhóm: Backend Services (10), Frontend & Mobile (4),
  AI & Content (2), Infra & Testing (2)... mỗi repo 1 dòng: làm gì + skill nào phụ trách.
- **Dependency map** — service nào gọi service nào (vd core ↔ autumn ↔ GTN).
- **Hạ tầng dùng chung** — bảng AWS account/region, bảng Database (repo nào dùng DB nào),
  branch strategy, deploy quick-reference.
- **Skill Navigation Guide** — "muốn làm X thì nạp skill nào".

Nguyên tắc: **chi tiết từng service nằm ở skill của service đó; skill platform chỉ giữ
"bản đồ + con trỏ"**, tránh lặp nội dung. Khi agent cần tổng quan/định tuyến → nạp
`vault22-platform`; khi đi sâu 1 service → nó nhảy sang skill chuyên biệt.

Hệ quả: AI có **2 tầng nhận thức** — *zoom-out* (platform skill: toàn cảnh, quan hệ giữa
các microservice) và *zoom-in* (per-service skill: chi tiết thực thi).

---

## 6. Quy trình dựng orchestrator cho hệ thống của bạn (step-by-step)

1. **Tạo repo orchestrator rỗng** (không chứa product code). Thêm `CLAUDE.md` mỏng +
   `README.md` onboarding.

2. **Gom mọi repo về làm sibling.** Viết `Makefile`:
   - Khai báo danh sách repo (`PRIMARY_REPOS`, và org thứ 2 nếu có).
   - Target `clone-all` (idempotent: bỏ qua repo đã có), `pull-all`, `status`, `branches`,
     `list`, `clean`. (Tham khảo Makefile repo này — guard `if [ -d ]` để chạy lại an toàn.)
   - Hỗ trợ `clone-whitelabel PROJECT=<code>` cho repo opt-in (white-label/khách hàng).

3. **Map mỗi service → 1 skill.** Với từng microservice tạo
   `.claude/skills/<service>/SKILL.md` theo template ở §3 và §10. Service nhỏ cùng họ →
   gộp 1 skill. Đẩy tài liệu dài vào `references/`.

4. **Viết lớp routing.** Trong `agent_docs/skill-routing.md`: bảng topic→skill và
   thư mục→skill cho mọi service. `CLAUDE.md` chỉ trỏ tới file này.

5. **Viết skill platform tổng** (§5): sơ đồ + phân nhóm repo + dependency + hạ tầng dùng chung.

6. **(Tuỳ chọn) Thêm cross-cutting:**
   - **Slash commands** (`.claude/commands/`) cho workflow lặp lại: `/create-pr`,
     `/cross-repo-search`, `/status-check`, `/sync-all`.
   - **Hooks** (`.claude/hooks/` + `settings.json`) cho hành vi tự động (nạp context lúc
     session start, khoá file tránh xung đột, log...).
   - **Knowledge base** (`vault/`) cho tài liệu offline (Jira/Confluence/runbook).

7. **Phân tầng kiến thức** để tránh trùng lặp (xem §7).

8. **Kiểm thử routing:** thử các câu/topic và `cd` vào từng thư mục → đúng skill được nạp.

---

## 7. Phân tầng kiến thức — đặt fact đúng chỗ (tránh trùng lặp)

| Tầng | Vị trí | Sở hữu cái gì |
|---|---|---|
| 1. Tooling & cách làm (person-agnostic) | `.claude/skills/*` | Workflow, lệnh, pattern của từng service |
| 2. Tri thức team dùng chung | `vault/{features,proposals,jira,...}` | Kiến trúc, runbook, thiết kế feature |
| 3. Ngữ cảnh cá nhân / phiên làm việc | brain/memory (gitignored) | State tạm, ghi chú in-flight |

Quy tắc: **quyết định tầng sở hữu fact TRƯỚC khi viết**. Nếu một topic đã nằm ở tầng 2 thì
skill chỉ **link tới**, không chép lại nội dung.

---

## 8. Quy tắc vàng (DO / DON'T)

**DO**
- Giữ `CLAUDE.md` mỏng; đẩy chi tiết vào skill; đẩy chi tiết sâu hơn vào `references/`.
- 1 skill = 1 service/domain, có `description` giàu trigger (từ khoá + thư mục).
- Làm Makefile idempotent (chạy lại không hỏng).
- Có 1 skill platform làm bản đồ tổng + skill chuyên biệt cho chi tiết.
- Mọi fact chỉ sống ở **một** tầng; nơi khác link tới.

**DON'T**
- ❌ Để code sản phẩm trong orchestrator (chỉ clone reference, sửa ở repo gốc).
- ❌ Nhồi bảng routing dài vào `CLAUDE.md` (tách `skill-routing.md`).
- ❌ Lặp nội dung giữa skill platform và skill service.
- ❌ Trả lời chủ đề đã có skill bằng kiến thức chung mà không nạp skill.
- ❌ Tạo skill "khổng lồ" cho mọi thứ — chia theo service/domain.

---

## 9. Vòng đời & bảo trì

- **Repo mới** → thêm vào `PRIMARY_REPOS` (Makefile) + tạo skill mới + thêm dòng vào
  routing + cập nhật phân nhóm trong skill platform.
- **Pull định kỳ** → `make pull-all` để bản reference không lệch repo thật.
- **Skill tiến hoá** → khi pattern/cạm bẫy mới xuất hiện, cập nhật `SKILL.md` (và
  `references/`), không để kiến thức chết trong đầu một người.
- **Đo độ "khớp"** → thỉnh thoảng thử vài prompt thật, xem agent có nạp đúng skill không;
  chỉnh lại `description`/routing nếu lệch.

---

## 10. Template SKILL.md (copy để bắt đầu một service mới)

```markdown
---
name: <service-slug>
description: Use this skill when working with <Service Name> (<repo-or-dir>/). Covers
  building, running, testing, the <pattern> architecture, and <key responsibilities>.
  Triggers include "<keyword1>", "<keyword2>", "<keyword3>", or working in the
  <repo-or-dir>/ directory.
---

# <Service Name> Skill

Một dòng: service này làm gì trong hệ thống.

## Overview
| Property | Value |
|----------|-------|
| Location | <path> |
| Framework | <lang/version> |
| Entry point | <solution/app> |
| Database | <db> |
| Port | <port> |

## Quick Commands
```bash
# Build / Run / Test (copy-paste được)
```

## Architecture & Patterns
- Pattern chính, naming convention, ranh giới module.

## Key Rules & Gotchas
- File/khu vực CẤM sửa, rule sharding/auth, lỗi hay gặp.

## How to Test
- Convention tên test + lệnh chạy.

## Related Skills
- Phụ thuộc / gọi tới: `<other-skill>`, `<other-skill>`.

## Reference Files
- `references/architecture.md`, `references/deployment.md` (đọc khi cần).
```

---

## 11. Áp dụng cho nhiều tool: GitHub Copilot, Codex, Cursor

**Nguyên tắc (nhắc lại):** giữ **một nguồn sự thật** (`.claude/skills/` +
`agent_docs/skill-routing.md`), mỗi tool chỉ thêm **lớp tương thích mỏng** trỏ về nguồn
đó. Repo này đã làm vậy cho Codex qua `AGENTS.md` + symlink `.agents/skills → .claude/skills`.
Copilot làm tương tự bằng cơ chế riêng của nó.

### Bảng ánh xạ khái niệm → cơ chế từng tool

| Khái niệm trong guide | Claude Code | GitHub Copilot | Codex / Cursor |
|---|---|---|---|
| Luật global (luôn nạp) | `CLAUDE.md` | `.github/copilot-instructions.md` + `AGENTS.md` | `AGENTS.md` |
| Skill mỗi service | `.claude/skills/<svc>/SKILL.md` | `.github/instructions/<svc>.instructions.md` (frontmatter `applyTo`); Copilot CLI: skill plugin | `.agents/skills/<svc>` (symlink) |
| Trigger theo **thư mục** | bảng working-dir → skill | `applyTo: "core/**"` trong instructions file | bảng routing dùng chung |
| Trigger theo **từ khoá** | frontmatter `description` | phần mô tả trong instructions file | frontmatter `description` |
| Workflow lặp lại (slash) | `.claude/commands/*.md` (`/create-pr`) | `.github/prompts/*.prompt.md` | đọc trong thân skill |
| Gọi skill **bằng tay** | `/skill-name` | prompt file; Copilot CLI: `skill` tool | `$skill-name` |
| Bản đồ toàn hệ thống | skill `vault22-platform` | `platform.instructions.md` (`applyTo: "**"`) | cùng skill, dùng chung |

### AGENTS.md = xương sống chung
`AGENTS.md` là chuẩn nhiều agent đọc được (Copilot coding agent, Codex, Cursor, Aider…).
Đặt ở root (và có thể nested trong từng repo con). Nội dung nên:
- Trỏ tới **nguồn skill thật** (`.claude/skills/`) và bảng routing (`agent_docs/skill-routing.md`) là hợp đồng dùng chung.
- Ghi luật: *"Khi tài liệu nhắc `/skill-name`, nạp skill đó TRƯỚC khi trả lời/hành động."*
- Giữ thay đổi workflow trong **thân skill** để mọi tool đồng bộ (đừng sửa riêng từng tool).

### Layout Copilot cụ thể (để Copilot tự hiểu & tự dựng được)
```
.github/
├── copilot-instructions.md             # = CLAUDE.md (luật global, Copilot luôn áp dụng)
├── instructions/
│   ├── vault22-backend.instructions.md     # applyTo: "core/**"
│   ├── core-microservices.instructions.md  # applyTo: "core.jill/**,core.jack/**,core.steph/**,Core.NAPI/**"
│   └── platform.instructions.md            # applyTo: "**"  (bản đồ toàn hệ thống)
└── prompts/
    ├── create-pr.prompt.md             # = /create-pr
    └── cross-repo-search.prompt.md     # = /cross-repo-search
AGENTS.md                               # xương sống chung (đã có sẵn ở repo này)
```

Mỗi file `*.instructions.md` chỉ là thân `SKILL.md` + frontmatter `applyTo`:
```markdown
---
applyTo: "core/**"
---
# Vault22 Backend
<copy y nội dung SKILL.md: Overview, Quick Commands, Patterns, Gotchas, ...>
```
→ `applyTo` chính là bản sao của **"directory-based skill selection"**: Copilot tự nạp
instructions khi bạn mở/sửa file khớp glob. Path-scope càng hẹp, nạp càng đúng.

### Giữ đồng bộ — không maintain 2 lần
1. Coi `.claude/skills/<svc>/SKILL.md` là **nguồn**.
2. Sinh `.github/instructions/<svc>.instructions.md` = thân bài skill + frontmatter
   `applyTo` lấy từ cột "Working Directory" trong `skill-routing.md` (có thể tự động bằng
   một script đọc bảng routing rồi xuất ra).
3. `copilot-instructions.md` = `CLAUDE.md` đã lược các phần Claude-specific (hooks, brain).
4. Khác biệt giữa các tool chỉ nằm ở **frontmatter + cú pháp gọi skill**, KHÔNG ở nội dung.

> Tóm tắt đa-tool: **nội dung = chung 1 nguồn; mỗi tool = 1 adapter mỏng.** Copilot đọc
> `AGENTS.md` + `.github/instructions/*` (với `applyTo`) là đủ để hiểu scope toàn hệ thống
> và dựng được orchestrator tương đương.

---

### TL;DR
Orchestrator = repo trung tâm **không chứa code**, gom mọi repo làm sibling, **đóng gói
mỗi service thành 1 skill** (file `SKILL.md` có frontmatter giàu trigger), thêm **lớp
routing** (topic→skill, thư mục→skill) để AI tự nạp đúng skill đúng lúc, và **1 skill
platform** làm bản đồ tổng để AI hiểu quan hệ giữa toàn bộ microservice. `CLAUDE.md` luôn
mỏng; chi tiết tiết lộ dần theo nhu cầu. **Đa-tool:** giữ 1 nguồn sự thật ở
`.claude/skills/`, mỗi tool thêm 1 lớp adapter mỏng — Claude dùng `CLAUDE.md`+skills,
Copilot dùng `.github/copilot-instructions.md`+`instructions/*.instructions.md` (`applyTo`),
Codex dùng `AGENTS.md`+`.agents/skills`. `AGENTS.md` là xương sống chung.
