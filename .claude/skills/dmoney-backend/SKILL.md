---
name: dmoney-backend
description: Use this skill when working with the dmoney-tracker .NET backend
  (dmoney-tracker-be/). Covers building, testing, running the Web.Api, Clean
  Architecture layers, custom CQRS, EF Core migrations, JWT auth, resx i18n and
  error codes. Triggers include "backend", "API", ".NET", "C#", "migration",
  "EF Core", "postgres schema", "JWT", "resx", "error code", "integration test",
  or working in the dmoney-tracker-be/ directory.
---

# dmoney-tracker Backend Skill

.NET 10 API for the money tracker. **Authoritative conventions live in
`../dmoney-tracker-be/CLAUDE.md` — read it before non-trivial work.** This skill is
the quick map.

## Overview

| Property | Value |
|---|---|
| Location | `../dmoney-tracker-be` |
| Framework | .NET 10, C#, minimal APIs |
| Solution | `DMoney.slnx` (5 projects: SharedKernel ← Domain ← Application ← Infrastructure ← Web.Api) |
| Database | PostgreSQL (EF Core + Npgsql), db `dmoney` |
| Port | 5113 |
| Tests | NUnit; unit (mocked DbContext) + integration (Testcontainers, needs Docker) + architecture (NetArchTest) |

## Quick commands

```bash
dotnet build DMoney.slnx                 # ZERO-warnings gate
dotnet test tests/Application.UnitTests  # fast loop, no Docker
dotnet test DMoney.slnx                  # all suites, needs Docker
dotnet run --project src/Web.Api        # :5113, auto-migrates in Development
dotnet dotnet-ef migrations add <Name> --project src/Infrastructure --startup-project src/Web.Api --output-dir Database/Migrations
```

## Key rules & gotchas (the ones that bite)

- Custom CQRS, **no MediatR**: `internal sealed` `*CommandHandler`/`*QueryHandler`
  returning `Result<T>` — never throw for domain failures. Register each handler
  explicitly in `Application/DependencyInjection.cs`.
- Migrations MUST use `--output-dir Database/Migrations`.
- `MapInboundClaims = false` + raw `"sub"` claim in `UserContext` are a pair.
- Other users' records → 404, never 403 (isolation via query predicates).
- `Money.Zero()` is a factory, not a shared instance (EF owned-type requirement).
- Every user-facing string: add key to BOTH `SharedResource.vi.resx` and `.en.resx`.
- Domain codes (categories, payment methods, card types) are lowercase strings
  validated against `IReadOnlyList<string> All` — mirror pattern for new code sets.

## Related skills

- `dmoney-platform` — cross-repo contracts (DTOs ↔ types.ts, codes, resx).
- `dmoney-web` — the consumer of every endpoint and resx key.
