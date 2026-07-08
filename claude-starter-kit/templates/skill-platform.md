---
name: platform
description: Whole-system map for __PROJECT__ — what each repo does, how the services
  connect, and which skill owns which area. Use when a question spans multiple services,
  when deciding where a change belongs, or when onboarding. Triggers include
  "architecture", "system overview", "which service", "how do services connect",
  "platform", "repo map".
---

# __PROJECT__ Platform Skill — bird's-eye view

One paragraph: what the product does, the main user-facing surfaces, and the high-level
data flow. <fill in>

## Repositories & owning skills

| Repo | What it does | Skill |
|---|---|---|
__ROWS:platform-repos__

## How the services connect

- <service A> → <service B> via <protocol> for <purpose>.
- (Keep the 5–10 most important edges; a diagram reference is fine.)

## Environments

| Env | URL / account | Notes |
|---|---|---|
| dev | <url> | |
| prod | <url> | read-only by default |

## Skill navigation guide

- To work on <area> → load `<skill>`.
- (Add rows as patterns emerge.)

> Keep this skill at MAP level: per-service detail lives in that service's skill —
> link to it, never restate it.
