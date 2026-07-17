# Demo saves (screenshot harness)

Hand-staged in-progress games for the App Store demo: boards arranged in the
app itself (flags where you put them), frozen here, and resumed verbatim by
every demo launch — identical in all languages and on all platforms.

**Dev-only.** The demo *scripts* copy these into the app's isolated demo save
directory before launch; nothing here is bundled into the shipped app, and the
app never reads the repo.

## Regenerate

1. `make demo-mac` — resume/arrange the boards exactly as they should look.
2. Quit the app (⌘Q — the exit autosave writes the final state).
3. `make demo-freeze` — copies the boards here.
4. Commit. Delete the files to fall back to the generated default boards.
