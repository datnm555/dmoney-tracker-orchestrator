---
description: Auto-draft a service skill by reading the actual repo clone — replaces hand-filling the SKILL.md template.
argument-hint: <repo> | all
---

# Populate Skill

Target: $ARGUMENTS  (`all` = every skill that still contains template placeholders — check with `make doctor`)

Draft `.claude/skills/<slug>/SKILL.md` from FACTS found in the sibling clone — never from
general knowledge of what such a service "usually" looks like.

## Steps

1. **Locate the clone.** The repo must exist as a sibling directory (`make clone-all`
   first if it doesn't).
2. **Read the evidence**, in this order:
   - `README*`, `CONTRIBUTING*`, `docs/` (if small)
   - Build files: `Makefile`, `package.json`, `*.sln`/`*.csproj`, `pyproject.toml`,
     `go.mod`, `pom.xml`, `build.gradle*`, `docker-compose*`, `Dockerfile`
   - CI: `.github/workflows/*`
   - Directory structure (top 2 levels) + the main entry point
3. **Fill every section** of the existing SKILL.md:
   - *Overview table*: framework + version, entry point, database, port — taken from
     config files, not guessed.
   - *Quick Commands*: build/run/test commands that actually exist in the build files,
     copy-paste runnable.
   - *Architecture & Patterns*: the dominant pattern actually observed (layering,
     naming conventions, module boundaries).
   - *Key Rules & Gotchas*: generated files not to hand-edit, auth/config peculiarities,
     env vars required to boot locally.
   - *Related Skills*: which sibling repos this one calls — grep for their names, URLs,
     or client packages.
4. **Rewrite the frontmatter `description`** to be trigger-rich: real domain keywords,
   service aliases people actually say, plus "working in the <repo>/ directory".
5. **Mark uncertainty.** Anything not verifiable from the repo → write `<verify: …>`,
   never invent.
6. **Report** which sections were auto-filled vs still need a human, then suggest
   topic→skill keyword rows to add to `agent_docs/skill-routing.md`.

After populating all repos: fill the "what it does" column in
`.claude/skills/platform/SKILL.md` and re-run `make doctor` until no placeholder
warnings remain.
