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

# App Store screenshots — see Scripts/asc/SCREENSHOTS.md. `make shots` is the
# whole flow: it launches the demo per language, prompts what to stage, and
# captures each shot itself, canonically named under shots/<platform>/<lang>/.
# The demo-* targets just launch the app for freehand poking.
.PHONY: shots
shots:  ## Guided screenshot capture: PLATFORM=iphone|ipad|mac [LANGS=en,fi,ja] [OUT=shots]
	@Scripts/shoot.sh

.PHONY: demo-freeze
demo-freeze:  ## Commit the Mac demo's current boards as the seeded saves (stage in-app, quit, run this)
	@src="$$HOME/Library/Containers/fi.misaki.donpa/Data/tmp/donpa-demo/saves"; \
	ls "$$src"/save-*.json >/dev/null 2>&1 || { echo "No demo saves found — stage boards in 'make demo-mac' first."; exit 1; }; \
	cp -v "$$src"/*.json Scripts/asc/demo-saves/
	@echo "Frozen. Commit Scripts/asc/demo-saves to ship these boards."

.PHONY: demo-iphone
demo-iphone: build-ios  ## Launch the iPhone simulator in demo mode (DEMO_LANG=en|fi|ja)
	@PLATFORM=iphone Scripts/demo.sh

.PHONY: demo-ipad
demo-ipad: build-ios  ## Launch the iPad simulator in demo mode (DEMO_LANG=en|fi|ja)
	@PLATFORM=ipad Scripts/demo.sh

.PHONY: demo-mac
demo-mac: build-mac  ## Launch the Mac app in demo mode (DEMO_LANG=en|fi|ja)
	@PLATFORM=mac Scripts/demo.sh

perf: build-mac  ## Headless macOS perf probe (CPU% + Time Profiler trace) of a heavy XXXL board
	@Scripts/perf-profile.sh

# App Store Connect achievement tooling. The runner self-manages a venv (deps
# in Scripts/asc/requirements.txt); achievements.json is the source of truth.
.PHONY: asc-medals
asc-medals:  ## Render the 29 achievement medal PNGs into Scripts/asc/medals
	@DONPA_MEDAL_ASC="$(CURDIR)/Scripts/asc/medals" DONPA_REPO_ROOT="$(CURDIR)" \
		swift test --package-path Packages/DonpaCore \
		--filter MedalGalleryRender/testRenderASCImages
	@echo "Rendered $$(ls Scripts/asc/medals/*.png | wc -l | tr -d ' ') medals."

.PHONY: asc-status
asc-status:  ## List Game Center achievements + completeness (reads ASC)
	@Scripts/asc/run.sh status

.PHONY: asc-sync
asc-sync:  ## Show what differs between achievements.json and ASC (dry run)
	@Scripts/asc/run.sh sync $(ARGS)

.PHONY: asc-sync-apply
asc-sync-apply:  ## Push achievements.json text/points changes to ASC (add ARGS="--images ..." for images)
	@Scripts/asc/run.sh sync --apply $(ARGS)

.PHONY: asc-listing
asc-listing:  ## Show what differs between listing.json and the ASC App Store listing (dry run)
	@Scripts/asc/run.sh listing $(ARGS)

.PHONY: asc-listing-apply
asc-listing-apply:  ## Push listing.json (description/keywords/etc.) to the ASC listing
	@Scripts/asc/run.sh listing --apply $(ARGS)

.PHONY: asc-release
asc-release:  ## Show which achievements would be added to review (dry run)
	@Scripts/asc/run.sh sync --release

.PHONY: asc-release-apply
asc-release-apply:  ## Add all achievements to review (create release records)
	@Scripts/asc/run.sh sync --release --apply

.PHONY: asc-shots
asc-shots:  ## Rename raw screenshots by capture order: DIR=<folder> PLATFORM=iphone|ipad|mac [LANGS=en,fi,ja]
	@Scripts/asc/run.sh organize $${PLATFORM:-iphone} $(DIR) $(if $(LANGS),--langs=$(LANGS),)

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

# The steps form a linear dependency chain — each requires the previous — so
# `make release` (an alias for the last step) runs them in order, and the order
# holds even under `make -j`. Running an intermediate target pulls in its
# predecessors; to repeat just one step (e.g. re-tag after a stalled merge),
# call its script directly (Scripts/release-tag.sh all) — the scripts re-derive
# their inputs from git + project.yml, so each stands alone.
.PHONY: release
release: release-distribute  ## Cut a release (PLATFORM=all|ios|macos, UPLOAD=0 to skip ASC)
	@echo "✓ release complete (PLATFORM=$(PLATFORM))."

.PHONY: release-build
release-build:  ## Like `release` but stop after export (no upload)
	@$(MAKE) release UPLOAD=0

.PHONY: release-preflight
release-preflight:  ## Release step 1: verify a clean, up-to-date base (main or release/X.Y.x)
	@Scripts/release-preflight.sh

.PHONY: release-publish
release-publish: release-preflight  ## Release step 2: bump, open auto-merging PR, wait for CI
	@Scripts/release-publish.sh $(PLATFORM)

.PHONY: release-tag
release-tag: release-publish  ## Release step 3: tag the merge commit + publish GitHub releases
	@Scripts/release-tag.sh $(PLATFORM)

.PHONY: release-distribute
release-distribute: release-tag  ## Release step 4: archive/export (+ upload unless UPLOAD=0)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS)

# Distribute is the likeliest step to fail (archive/export/ASC upload) and is
# safe to repeat. This standalone retry has NO prereqs — it re-distributes an
# already-tagged release without touching git/PR/tags, after verifying the tag
# for the current version+build exists.
.PHONY: release-distribute-retry
release-distribute-retry:  ## Re-distribute an already-tagged release (no PR/tag steps)
	@Scripts/release-distribute.sh $(PLATFORM) $(DIST_FLAGS) --require-tag

# Upload the package already in dist/ (from a prior `release-build`) without
# rebuilding — for when export succeeded but only the ASC upload failed.
.PHONY: release-upload
release-upload:  ## Upload the already-built dist/ package (no rebuild)
	@Scripts/release-distribute.sh $(PLATFORM) --upload-only

.PHONY: clean
clean:  ## Remove the generated project + local build output
	@rm -rf Donpa.xcodeproj .build-xcode
	@echo "removed Donpa.xcodeproj and .build-xcode"
