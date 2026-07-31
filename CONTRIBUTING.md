# Contributing to Donpa Squad

Thanks for your interest! The full contributor guide — project layout, build &
test commands, code style, the asset pipeline, and conventions — lives in
**[AGENTS.md](AGENTS.md)**, which is the single canonical source for both humans
and AI coding agents. This file just points you there so it's easy to find.

Quick orientation:

- **Build & run / tests:** see [AGENTS.md](AGENTS.md) (or the
  [README's Development section](README.md#development)). In short: Xcode 16+ and
  XcodeGen; `make test` runs the logic tests, `make run-mac` / `make run-iphone` / `make run-ipad`
  build and launch.
- **Architecture / why things are the way they are:**
  [ARCHITECTURE.md](ARCHITECTURE.md).
- **What's planned:** [ROADMAP.md](ROADMAP.md). **What's changed:**
  [CHANGELOG.md](CHANGELOG.md).

Pull requests:

- Branch off `main`; keep the change focused.
- Match the surrounding code style. CI must stay green — SwiftLint +
  swift-format, the logic tests (with coverage), and both platform builds all run
  on CI; run `make test` and the linters locally before pushing.
- Describe what changed and why in the PR body.

Licensing:

- By contributing you agree your contributions are licensed under the
  repository's [MIT License](LICENSE), which includes distribution as part of
  the shipped app (Donpa Squad ships on the App Store).
- You confirm the contribution is your own work and that you have the right to
  submit it under that license — not copied from code you don't have the right
  to relicense (an employer's, or an incompatibly-licensed project's).
- Ideas and suggestions in issues are welcome and, being ideas, aren't
  something anyone owns — feel free to open them; implementing them is fine.
- Art assets may carry a separate license in the future — see the
  [roadmap](ROADMAP.md).
