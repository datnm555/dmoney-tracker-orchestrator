# __PROJECT__ Orchestrator Makefile
SHELL := /bin/bash
ORG := __ORG__
GIT_PROTOCOL ?= ssh

# Entries may be "repo" (cloned from $(ORG)) or "org/repo" (explicit org).
PRIMARY_REPOS := \
__ROWS:makefile-repos__

# Real escape bytes via $(shell printf) so plain `echo` renders colors in any shell.
GREEN := $(shell printf '\033[0;32m')
YELLOW := $(shell printf '\033[0;33m')
RED := $(shell printf '\033[0;31m')
NC := $(shell printf '\033[0m')

.PHONY: help clone-all pull-all status branches list doctor

help:
	@echo "$(GREEN)__PROJECT__ Orchestrator$(NC)"
	@echo "  make clone-all   - clone all repos as siblings"
	@echo "  make pull-all    - pull latest for all cloned repos"
	@echo "  make status      - repos with uncommitted changes"
	@echo "  make branches    - current branch per repo"
	@echo "  make list        - list repos + clone status"
	@echo "  make doctor      - validate orchestrator structure (skills, routing)"

clone-all:
	@for repo in $(PRIMARY_REPOS); do \
		dir=$${repo##*/}; \
		case "$$repo" in */*) path=$$repo;; *) path=$(ORG)/$$repo;; esac; \
		if [ -d "$$dir" ]; then echo "$(YELLOW)$$dir exists, skipping$(NC)"; \
		elif [ "$(GIT_PROTOCOL)" = "https" ]; then git clone https://github.com/$$path.git || echo "$(RED)failed $$repo$(NC)"; \
		else git clone git@github.com:$$path.git || echo "$(RED)failed $$repo$(NC)"; fi; \
	done

pull-all:
	@for repo in $(PRIMARY_REPOS); do \
		dir=$${repo##*/}; \
		if [ -d "$$dir" ]; then echo "$(GREEN)pulling $$dir$(NC)"; (cd $$dir && git pull --rebase) || echo "$(RED)failed $$dir$(NC)"; fi; \
	done

status:
	@for repo in $(PRIMARY_REPOS); do \
		dir=$${repo##*/}; \
		if [ -d "$$dir" ]; then s=$$(cd $$dir && git status -s); [ -n "$$s" ] && { echo "$(YELLOW)$$dir:$(NC)"; echo "$$s"; } || true; fi; \
	done

branches:
	@for repo in $(PRIMARY_REPOS); do \
		dir=$${repo##*/}; \
		if [ -d "$$dir" ]; then b=$$(cd $$dir && git rev-parse --abbrev-ref HEAD); printf "$(YELLOW)%-30s$(NC) %s\n" "$$dir:" "$$b"; \
		else printf "$(RED)%-30s$(NC) %s\n" "$$dir:" "(not cloned)"; fi; \
	done

list:
	@for repo in $(PRIMARY_REPOS); do \
		dir=$${repo##*/}; \
		if [ -d "$$dir" ]; then echo "  [cloned]  $$dir"; else echo "  [missing] $$dir"; fi; \
	done

doctor:
	@ok=1; \
	if [ ! -f agent_docs/skill-routing.md ]; then echo "$(RED)x missing agent_docs/skill-routing.md$(NC)"; ok=0; fi; \
	if [ ! -f .claude/skills/platform/SKILL.md ]; then echo "$(YELLOW)! no platform skill (.claude/skills/platform/SKILL.md)$(NC)"; \
	elif grep -q '<what it does>' .claude/skills/platform/SKILL.md; then echo "$(YELLOW)! platform skill repo table not filled in$(NC)"; fi; \
	if [ ! -f .gitignore ]; then echo "$(YELLOW)! no .gitignore — reference clones may get committed into the orchestrator$(NC)"; fi; \
	for repo in $(PRIMARY_REPOS); do \
		dir=$${repo##*/}; slug=$$(echo "$$dir" | tr '[:upper:]' '[:lower:]'); \
		f=".claude/skills/$$slug/SKILL.md"; \
		if [ ! -f "$$f" ]; then echo "$(RED)x missing skill: $$f$(NC)"; ok=0; \
		elif grep -qE '<keyword>|<lang/version>' "$$f"; then echo "$(YELLOW)! placeholders left in $$f — run /populate-skill $$dir$(NC)"; fi; \
		if [ -f .gitignore ] && ! grep -qxF "$$dir/" .gitignore; then echo "$(YELLOW)! reference clone '$$dir/' not in .gitignore — add it so the clone isn't committed$(NC)"; fi; \
	done; \
	for f in .claude/skills/*/SKILL.md; do \
		s=$$(basename $$(dirname "$$f")); [ "$$s" = platform ] && continue; \
		found=0; for repo in $(PRIMARY_REPOS); do dir=$${repo##*/}; slug=$$(echo "$$dir" | tr '[:upper:]' '[:lower:]'); [ "$$slug" = "$$s" ] && { found=1; break; }; done; \
		[ $$found -eq 0 ] && echo "$(YELLOW)! skill '$$s' has no PRIMARY_REPOS entry — add the repo to this Makefile + the routing tables$(NC)" || true; \
	done; \
	if [ $$ok -eq 1 ]; then echo "$(GREEN)ok doctor: structure OK (warnings above, if any, are fill-in reminders)$(NC)"; else echo "$(RED)doctor: structural problems found$(NC)"; exit 1; fi
