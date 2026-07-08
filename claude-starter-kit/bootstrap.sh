#!/usr/bin/env bash
# bootstrap.sh — scaffold a Claude Code orchestrator for ANY multi-repo / multi-service
# project. One source of truth: .claude/skills/ (each service = one SKILL.md).
# This kit is Claude-only.
#
# All file bodies live in templates/ next to this script — edit them there, not here.
# Idempotent: never overwrites a file that already exists, so you can re-run after
# adding repos without losing hand-edited skills.
#
# Usage:
#   PROJECT_NAME="Acme" GIT_ORG="acme-inc" \
#   REPOS="api web worker other-org/infra" \      # entries: "repo" or "org/repo"
#   TARGET_DIR=./acme-orchestrator \
#   ./bootstrap.sh
#
# Then: make clone-all, then in Claude Code run /populate-skill <repo> to auto-draft
# each skill from the actual clone (or fill .claude/skills/<repo>/SKILL.md by hand).
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-MyProject}"
GIT_ORG="${GIT_ORG:-my-org}"
REPOS="${REPOS:-service-a service-b service-c}"
TARGET_DIR="${TARGET_DIR:-.}"

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL_DIR="$KIT_DIR/templates"
[ -d "$TPL_DIR" ] || { echo "ERROR: templates/ not found next to bootstrap.sh ($TPL_DIR) — copy the whole claude-starter-kit/ directory." >&2; exit 1; }

mkdir -p "$TARGET_DIR"; cd "$TARGET_DIR"
mkdir -p .claude/skills .claude/commands agent_docs

ROWS_DIR="$(mktemp -d)"; trap 'rm -rf "$ROWS_DIR"' EXIT

note() { printf '  %s\n' "$*"; }

# render <template-relative-path> <dest>
# - substitutes __PROJECT__ / __ORG__ / __REPO__ / __SLUG__ tokens
# - replaces any line "__ROWS:<name>__" with the contents of $ROWS_DIR/<name>
# - writes only if <dest> does not exist yet
render() {
  local tpl="$TPL_DIR/$1" dest="$2"
  [ -f "$tpl" ] || { echo "ERROR: missing template: $tpl" >&2; exit 1; }
  if [ -e "$dest" ]; then note "skip (exists): $dest"; return; fi
  mkdir -p "$(dirname "$dest")"
  sed -e "s|__PROJECT__|$PROJECT_NAME|g" \
      -e "s|__ORG__|$GIT_ORG|g" \
      -e "s|__REPO__|${REPO:-}|g" \
      -e "s|__SLUG__|${SLUG:-}|g" "$tpl" \
  | awk -v rowsdir="$ROWS_DIR" '
      /^__ROWS:.*__$/ {
        name = substr($0, 8, length($0) - 9)
        file = rowsdir "/" name
        while ((getline line < file) > 0) print line
        close(file)
        next
      }
      { print }' > "$dest"
  note "created: $dest"
}

echo "Scaffolding '$PROJECT_NAME' orchestrator in: $(pwd)"
echo "Repos: $REPOS"

# ---------------- row fragments generated from $REPOS (consumed by __ROWS:...__ markers)
: > "$ROWS_DIR/makefile-repos"
: > "$ROWS_DIR/dir-skill"
: > "$ROWS_DIR/repo-list"
: > "$ROWS_DIR/platform-repos"
: > "$ROWS_DIR/gitignore-repos"
for r in $REPOS; do
  dir="${r##*/}"
  slug="$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')"
  printf '\t%s \\\n' "$r"                                    >> "$ROWS_DIR/makefile-repos"
  printf '| `%s/` | `%s` |\n' "$dir" "$slug"                 >> "$ROWS_DIR/dir-skill"
  printf -- '- %s\n' "$r"                                    >> "$ROWS_DIR/repo-list"
  printf '| `%s` | <what it does> | `%s` |\n' "$dir" "$slug" >> "$ROWS_DIR/platform-repos"
  printf '%s/\n' "$dir"                                      >> "$ROWS_DIR/gitignore-repos"
done

# ---------------- global files
render gitignore         .gitignore
render CLAUDE.md         CLAUDE.md
render Makefile          Makefile
render skill-routing.md  agent_docs/skill-routing.md
render skill-platform.md .claude/skills/platform/SKILL.md

# ---------------- generic workflow commands
for c in create-pr pr-review cross-repo-search status-check populate-skill; do
  render "commands/$c.md" ".claude/commands/$c.md"
done

# ---------------- per-repo skill
for r in $REPOS; do
  REPO="${r##*/}"
  SLUG="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"
  render skill-service.md ".claude/skills/$SLUG/SKILL.md"
done

# ---------------- kit version stamp (always refreshed — metadata, not content)
if [ -f "$KIT_DIR/VERSION" ]; then
  cp "$KIT_DIR/VERSION" .orchestrator-kit-version
  note "stamped: .orchestrator-kit-version ($(cat .orchestrator-kit-version))"
fi

cat <<EOF

Done. Next steps:
  1. cd "$TARGET_DIR"
  2. make clone-all               # pull your real repos as siblings (read-only ref)
  3. In Claude Code: /populate-skill <repo>  (or 'all') — auto-drafts each
     .claude/skills/<repo>/SKILL.md from the actual clone. Review what it wrote.
  4. Review .claude/skills/platform/SKILL.md — fill the repo table + service relationships.
  5. Add topic->skill keyword rows in agent_docs/skill-routing.md.
  6. make doctor                  # validates structure + lists skills still on placeholders
  7. Re-run this script anytime you add repos (REPOS="...") — existing files are kept.
     A new repo gets its skill generated; add it to the Makefile PRIMARY_REPOS, the
     routing tables, and .gitignore yourself ('make doctor' reminds you).
EOF
