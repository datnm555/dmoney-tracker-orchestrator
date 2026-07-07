# dmoney-tracker orchestrator — sibling repos live in the PARENT directory.
REPOS := dmoney-tracker-be dmoney-tracker-web
GIT_BASE := git@github.com:datnm555
PARENT := ..

.PHONY: help clone-all pull-all status branches list

help:
	@echo "Targets:"
	@echo "  clone-all  Clone missing sibling repos into $(PARENT)/ (idempotent)"
	@echo "  pull-all   git pull --ff-only every sibling repo"
	@echo "  status     git status -sb for every sibling repo"
	@echo "  branches   Current branch of every sibling repo"
	@echo "  list       List managed repos"

clone-all:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			echo "skip  $$repo (already cloned)"; \
		else \
			echo "clone $$repo"; \
			git clone "$(GIT_BASE)/$$repo.git" "$(PARENT)/$$repo"; \
		fi; \
	done

pull-all:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			echo "== $$repo =="; \
			git -C "$(PARENT)/$$repo" pull --ff-only; \
		fi; \
	done

status:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			echo "== $$repo =="; \
			git -C "$(PARENT)/$$repo" status -sb; \
		fi; \
	done

branches:
	@for repo in $(REPOS); do \
		if [ -d "$(PARENT)/$$repo/.git" ]; then \
			printf "%-24s %s\n" "$$repo" "$$(git -C $(PARENT)/$$repo branch --show-current)"; \
		fi; \
	done

list:
	@for repo in $(REPOS); do echo "$$repo"; done
