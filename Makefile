.DEFAULT_GOAL := help

VERSION ?= $(filter-out dmg debug help,$(MAKECMDGOALS))

.PHONY: help debug dmg
help:
	@echo "make debug        Build dist/DeskPuff.app in Debug mode"
	@echo "make dmg 0.1.1    Build a Release DMG in dist/"

debug:
	@DESKPUFF_CONFIGURATION=debug ./scripts/build-app.sh

ifneq ($(filter-out dmg debug help,$(MAKECMDGOALS)),)
.PHONY: $(filter-out dmg debug help,$(MAKECMDGOALS))
$(filter-out dmg debug help,$(MAKECMDGOALS)):
	@:
endif

dmg:
	@test -n "$(VERSION)" || { echo "Usage: make dmg 0.1.1" >&2; exit 2; }
	@./scripts/make-dmg.sh "$(VERSION)"
