---
name: dmoney-web
description: Use this skill when working with the dmoney-tracker React frontend
  (dmoney-tracker-web/). Covers Vite, React 19, TypeScript, Tailwind v4, shadcn/ui,
  Recharts, vitest, axios API layer, i18n labels and routing. Triggers include
  "frontend", "web", "UI", "React", "Tailwind", "shadcn", "component", "page",
  "chart", "vitest", "i18n label", or working in the dmoney-tracker-web/ directory.
---

# dmoney-tracker Web Skill

React SPA (Vietnamese-first). **Authoritative conventions live in
`../dmoney-tracker-web/CLAUDE.md` — read it before non-trivial work.**

## Overview

| Property | Value |
|---|---|
| Location | `../dmoney-tracker-web` |
| Framework | Vite + React 19 + TypeScript |
| UI | Tailwind v4 + shadcn/ui (vendored in `src/components/ui/`), lucide-react icons, sonner toasts |
| Charts | Recharts (pure data transforms in `src/utils/chartData.ts`) |
| Theme | primary `#6C4CF1`, zinc neutrals, radius 8px, font Be Vietnam Pro (`src/index.css`) |
| Tests | vitest + Testing Library (jsdom) |
| Port | 5173 dev / 8080 docker |

## Quick commands

```bash
npm run dev     # :5173, needs api at VITE_API_URL (default http://localhost:5113)
npm test        # vitest run
npm run build   # tsc -b && vite build (type-checks tests too)
npm run lint    # oxlint
```

## Key rules & gotchas

- ALL user-facing strings come from the backend `GET /resources` — `t(key)` falls
  back silently to the raw key; add keys to BOTH resx files in the be repo FIRST.
- `src/api/client.ts` interceptors: Bearer token + `lang` param on every call;
  401 → clear storage + redirect /login. `STORAGE_KEYS` are load-bearing.
- Pages: `/app/dashboard` (Tổng quan), `/app/transactions` (Giao dịch);
  `/app/summary` redirects to transactions. Auth pages: `/login`, `/register`.
- Code sets comment-synced with the be repo: `src/utils/categories.ts`,
  `src/utils/paymentMethods.ts`. DTO mirrors: `src/api/types.ts`.
- shadcn components are vendored — edit `src/components/ui/*` like normal code;
  add new ones with `npx shadcn@latest add -y <name>`.
- Tests mock `../api/resourceApi` so `t()` returns raw keys; assert on keys.

## Related skills

- `dmoney-backend` — API shapes, resx keys, error codes.
- `dmoney-platform` — ports, docker, cross-repo contract list.
