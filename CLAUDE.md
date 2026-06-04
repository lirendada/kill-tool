# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KillTool is a native macOS menu-bar app (`LSUIElement`, no Dock icon) that scans the current user's
development processes, traces each one back to its launching tool (Claude Code / Codex / VS Code /
Terminal), and lets the user selectively stop or force-kill them. Pure Swift, zero third-party
dependencies, macOS 13+ / Swift 5.9+.

## Commands

```bash
swift build                      # debug build
swift build -c release           # release build → .build/release/KillTool
swift run                        # build & launch the menu-bar app
scripts/test.sh                  # full test suite (build + behavior tests + packaging tests)
scripts/package-app.sh           # build a signed KillTool.app bundle → dist/ (prints bundle path)
swift run KillToolCoreBehaviorTests   # core behavior tests only
```

`scripts/test.sh` is the authoritative test entry point and runs three phases in order:
`swift build`, then `swift run KillToolCoreBehaviorTests`, then every `Tests/Packaging/*.sh`.

**Running a single test:** there is no test filter. The behavior suite is a plain executable whose
test functions are invoked by a flat call list at the bottom of
`Tests/KillToolCoreBehaviorTests/main.swift` — to run one in isolation, temporarily comment out the
others there. Packaging tests are individual scripts: `bash Tests/Packaging/<name>.sh`.

## Architecture

Three SPM targets (see `Package.swift`):
- **`KillToolCore`** (library) — all logic, **no UI imports, every type `Sendable`**. Keep it that way.
- **`KillToolApp`** (executable) — AppKit `NSStatusItem`/`NSPopover` + SwiftUI, all `@MainActor`.
- **`KillToolCoreBehaviorTests`** (executable) — the test runner (not XCTest; see Testing).

### Scan → classify → display pipeline

`ProcessScanner.scanDetailed()` runs three external commands **concurrently** (`captureAll`, a
`DispatchGroup` fan-out) and merges them by PID:
1. `/bin/ps -axo …` → the process table (parsed by `parsePSRow`)
2. `lsof … -d cwd` → working directory per PID (`parseWorkingDirectories`)
3. `lsof … -iTCP -sTCP:LISTEN` → listening ports per PID (`parseListeningPortDetails`)

The merged `RawProcess` rows flow through `ProcessScanner.classify(...)`:
`ProcessClassifier` assigns **source / kind / safety** → `ProjectResolver` assigns **project** →
rows are filtered by `isDevelopmentCandidate` (drops plain shells/apps with no port) → sorted by
source priority. Output is `[DevProcess]` wrapped in a `ProcessScanResult` (processes + scan errors).

**Instantaneous CPU is computed across scans, not within one.** `ps %cpu` is a *lifetime average*
that barely moves between refreshes, so the displayed CPU is derived by diffing accumulated CPU time:
`ps time=` → `RawProcess.cpuTimeSeconds` → `CPUSampler.instantaneousCPU` diffs against the previous
per-PID sample held in `ProcessStore.previousSamples` (keyed with `startedAt` to survive PID reuse) →
fills `DevProcess.instantaneousCPUPercent`, which `ProcessDisplayFormatter` prefers over the lifetime
average. This is why the refresh interval is short and why the store keeps a per-PID sample snapshot.

`ProcessClassifier` is rule-based and is the main extension point for tool/server support:
- **source**: walks the parent (`ppid`) ancestor chain and picks the highest-priority matched
  marker — Claude Code > Codex > VS Code > Terminal (`ProcessSource.priority`).
- **kind**: command-line substring matching (`devServer`, `mcp`, `database`, `docker`, …).
- **safety**: `protected` (apps, `claude`, other users — never killable), `warn` (databases/docker,
  >8h runtime, rootless shells), `safe` (dev servers / MCP / workers). Adding a new dev server or
  MCP pattern means editing the substring lists here.

### State & views

`ProcessStore` (`@MainActor ObservableObject`) holds scan results and derives `ProcessSection`s for
three view modes — **by source / by project / by port** (`ProcessViewMode`) — plus a **sort mode**
(default / CPU / memory, `ProcessSortMode`). Default builds parent/child **tree rows** (`treeRows`);
sorting by CPU/memory flattens each section to a descending list (`rows(for:)`). It handles search
filtering, and high-CPU rows (≥ `ProcessStore.highCPUThreshold`) are highlighted in `ProcessRowView`.
`ProcessDashboardView` / `ProcessRowView` render it; `ProcessDisplayFormatter` (in Core) produces the
human-readable titles, command labels, and CPU/memory badges. `PortCategory.classify` buckets
listening ports for the port view.

**Auto-refresh is owned by the view lifecycle, not the AppDelegate.** `ProcessDashboardView.onAppear`
calls `refresh()` + `startAutoRefresh()` (3s timer while the panel is open); `onDisappear` and
popover-close stop it. Do not move polling into `AppDelegate` — a packaging test enforces this.

### Kill safety model

`ProcessController.stop`/`forceKill` always re-verifies process identity before signaling:
`ProcessIdentityVerifying.matches` runs a fresh `ps -p <pid>` and compares user + full command line,
guarding against PID reuse. Only then does `ProcessSignalSending.send` call `Darwin.kill` (SIGTERM
for stop, SIGKILL for force). Protected processes cannot be selected (`toggleSelection` guards;
checkbox disabled). `ProcessController`, its verifier, and its signal sender are all injected
protocols — tests substitute `RejectingProcessIdentityVerifier` / `RecordingProcessSignalSender`.

`ProcessCommandRunner.run` wraps every external command with a timeout (SIGTERM → SIGKILL escalation)
and surfaces non-zero exits with a stderr summary as `ProcessCommandError`.

## Testing conventions

Two distinct test styles, both run by `scripts/test.sh`:

1. **Behavior tests** (`Tests/KillToolCoreBehaviorTests/main.swift`) — a hand-rolled runner, **not
   XCTest**. Assertions use `expectEqual(...)` which prints and `exit(1)`s on failure. To add a test:
   write a `func test…()` and append a call to the list at the bottom of the file.

2. **Packaging/architecture-guard tests** (`Tests/Packaging/*.sh`) — bash scripts that mostly **grep
   source files for exact strings** to lock in architectural invariants (dependency injection of the
   scanner, view-owned refresh, PID-level failure messages, port view mode, scan-error wording,
   status-item menu). ⚠️ These assert on literal source text — refactoring or rewording the guarded
   files (especially `ProcessStore.swift`, `KillToolMain.swift`) will break them even when behavior is
   unchanged. When you touch those files, read the relevant `Tests/Packaging/*.sh` and update its
   `grep` patterns to match.

## Conventions

- **UI strings are Chinese** (`displayName`s, dialog text, status summaries). Several packaging tests
  grep for exact Chinese strings — keep wording in sync with the guards.
- Core stays UI-free and fully `Sendable`; the app layer is `@MainActor`.
- No third-party dependencies — prefer the existing patterns (raw `Process`, `lsof`/`ps` parsing,
  protocol injection) over adding packages.
- Design rationale lives in `docs/superpowers/specs/` and `docs/superpowers/plans/` (note: the plan
  predates the final implementation and mentions XCTest, which was not adopted).
