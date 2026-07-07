# Skill Routing

Always load the matching skill BEFORE answering. Manual override: `/dmoney-platform`,
`/dmoney-backend`, `/dmoney-web`.

## By topic

| User says / topic | Skill | Examples |
|---|---|---|
| system architecture, how repos relate, ports, docker, deployment, cross-repo contracts | `dmoney-platform` | "how does web talk to api?", "what runs on 5113?" |
| .NET, API, C#, CQRS, EF Core, migrations, postgres schema, JWT auth, resx, error codes, integration tests | `dmoney-backend` | "add a field to Transaction", "why 401?" |
| React, UI, Tailwind, shadcn, Recharts, vitest, i18n labels, axios, routing, pages | `dmoney-web` | "restyle the dashboard", "add a filter tab" |
| transactions/categories/payment methods (data model + API) | `dmoney-backend` | "validate card type" |
| transactions/categories/payment methods (display + forms) | `dmoney-web` | "the badge shows the wrong label" |

## By working directory

| Working directory | Skill | Notes |
|---|---|---|
| `dmoney-tracker-be/` | `dmoney-backend` | .NET 10 API |
| `dmoney-tracker-web/` | `dmoney-web` | React frontend |
| `dmoney-tracker-orchestrator/` | `dmoney-platform` | this repo — system map |

Cross-repo work (contract changes, full-stack features): load `dmoney-platform`
plus each affected service skill.
