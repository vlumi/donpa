# Donpa — command-line build/run/test, so you never have to open Xcode.
#
# The Scripts/*.sh do the actual work (one job each); this Makefile wires up the
# dependencies (e.g. the Xcode project is regenerated only when project.yml or
# an Info.plist changes) and gives short targets. Run `make` (or `make help`)
# to list them.

.DEFAULT_GOAL := help

.PHONY: help
help:  ## List the available commands
	@echo "Donpa — available make targets:"
	@echo
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*## "} {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# Inputs xcodegen reads — regenerate the project when any of these change.
PROJECT_INPUTS := project.yml \
	$(wildcard Sources/*/Info.plist) \
	$(wildcard Sources/*/*.xcstrings)

# File target: the generated project depends on its inputs, so `make` skips the
# regen when nothing changed (and reruns it when project.yml etc. are edited).
Donpa.xcodeproj: $(PROJECT_INPUTS)
	@Scripts/generate.sh

.PHONY: generate
generate: Donpa.xcodeproj  ## Regenerate Donpa.xcodeproj from project.yml (if stale)

.PHONY: run-mac
run-mac: Donpa.xcodeproj  ## Build + launch the macOS app
	@Scripts/run.sh

.PHONY: run-ios
run-ios: Donpa.xcodeproj  ## Build + launch in an iOS simulator
	@Scripts/run-ios.sh

.PHONY: build-mac
build-mac: Donpa.xcodeproj  ## Build the macOS app
	@Scripts/build.sh macos

.PHONY: build-ios
build-ios: Donpa.xcodeproj  ## Build the iOS app (simulator)
	@Scripts/build.sh ios

# Logic tests run straight from the Swift package — no Xcode project involved.
.PHONY: test
test:  ## Run the package logic tests (no Xcode project needed)
	@Scripts/test.sh

# UI tests are local-only (CI never runs `xcodebuild test`); they drive the
# built iOS app in a simulator.
.PHONY: uitest
uitest: Donpa.xcodeproj  ## Run the local-only iOS UI tests (simulator)
	@Scripts/uitest.sh

# ── Release lane ──────────────────────────────────────────────────────────────
# The cut is split by concern, one script each, chained here in order:
#   preflight → publish → tag → distribute
# The pure ends (preflight, tag, distribute) re-derive their inputs from git +
# project.yml, so each runs standalone. The dirty middle (publish: version-bump
# prompts + auto-merging PR + CI-wait) is the one stateful script; state crosses
# to the later steps via the merged commit on main, not through Make.
#
# PLATFORM selects scope (default all); UPLOAD=0 stops after export (no ASC
# upload). The steps are a linear dependency chain so they stay ordered even
# under `make -j`. Run from a clean, up-to-date main.
PLATFORM ?= all
UPLOAD ?= 1
DIST_FLAGS := $(if $(filter 0,$(UPLOAD)),--no-upload,)

# `release` runs the four steps in order within one recipe (not as prerequisites)
# so the individual step targets below stay independently runnable — e.g. re-run
# `make release-tag` after fixing a stalled auto-merge, without re-opening a PR.
.PHONY: release
release:  ## Cut a release (PLATFORM=all|ios|macos, UPLOAD=0 to skip ASC)
	@Scripts/release-preflight.sh
	@Scripts/release-publish.sh $(PLATFORM)
	@Scripts/release-tag.sh $(PLATFORM)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS)
	@echo "✓ release complete (PLATFORM=$(PLATFORM))."

.PHONY: release-build
release-build:  ## Like `release` but stop after export (no upload)
	@$(MAKE) release UPLOAD=0

# The steps, individually runnable (each re-derives its inputs from git/project.yml).
.PHONY: release-preflight
release-preflight:  ## Release step 1: verify clean, up-to-date main
	@Scripts/release-preflight.sh

.PHONY: release-publish
release-publish:  ## Release step 2: bump, open auto-merging PR, wait for CI
	@Scripts/release-publish.sh $(PLATFORM)

.PHONY: release-tag
release-tag:  ## Release step 3: tag the merge commit + publish GitHub releases
	@Scripts/release-tag.sh $(PLATFORM)

.PHONY: release-distribute
release-distribute:  ## Release step 4: archive/export (+ upload unless UPLOAD=0)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS)

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Donpa.xcodeproj .build-xcode
	@echo "removed Donpa.xcodeproj and .build-xcode"
