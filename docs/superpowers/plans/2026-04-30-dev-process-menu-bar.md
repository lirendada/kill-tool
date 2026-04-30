# Dev Process Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pure Swift macOS menu bar app that shows all relevant development processes, labels their source, and lets the user manually stop selected processes.

**Architecture:** The app is a Swift Package with a reusable `KillToolCore` library and a `KillToolApp` executable. Core owns process models, scanning, classification, project resolution, and signal delivery; the app target owns `NSStatusItem`, `NSPopover`, and SwiftUI views.

**Tech Stack:** Swift 5.9+, Swift Package Manager, AppKit, SwiftUI, XCTest, macOS 13+.

---

## File Structure

- Create `Package.swift`: SwiftPM package, executable target, core library target, test target.
- Create `Sources/KillToolCore/Models.swift`: enums and `DevProcess` model.
- Create `Sources/KillToolCore/ProcessClassifier.swift`: source, kind, and safety classification.
- Create `Sources/KillToolCore/ProjectResolver.swift`: project name/path inference.
- Create `Sources/KillToolCore/ProcessScanner.swift`: runs `/bin/ps` and `/usr/sbin/lsof`, parses process snapshots and listening ports.
- Create `Sources/KillToolCore/ProcessController.swift`: sends `SIGTERM` and `SIGKILL`.
- Create `Sources/KillToolApp/main.swift`: menu bar application entry.
- Create `Sources/KillToolApp/ProcessStore.swift`: observable state, refresh, selection, actions.
- Create `Sources/KillToolApp/Views/ProcessDashboardView.swift`: popover root UI.
- Create `Sources/KillToolApp/Views/ProcessRowView.swift`: tree rows and process rows.
- Create `Tests/KillToolCoreTests/ProcessClassifierTests.swift`: source/kind/safety tests.
- Create `Tests/KillToolCoreTests/ProjectResolverTests.swift`: cwd and argv project inference tests.

## Tasks

### Task 1: Package And Failing Classifier Tests

- [ ] Create SwiftPM package files and core test files.
- [ ] Add tests for source priority, Codex detection, MCP kind, dev server kind, database warning, and protected app processes.
- [ ] Run `swift test --filter ProcessClassifierTests`; expected result is a compile failure because `KillToolCore` types do not exist.

### Task 2: Core Models And Classifier

- [ ] Implement `DevProcess`, `ProcessSource`, `ProcessKind`, `SafetyLevel`, and `ProcessClassifier`.
- [ ] Run `swift test --filter ProcessClassifierTests`; expected result is all classifier tests passing.

### Task 3: Project Resolver Tests And Implementation

- [ ] Add tests for resolving project roots from cwd marker files and argv paths.
- [ ] Run `swift test --filter ProjectResolverTests`; expected result is failure before resolver implementation.
- [ ] Implement `ProjectResolver`.
- [ ] Run `swift test --filter ProjectResolverTests`; expected result is all resolver tests passing.

### Task 4: Scanner And Controller

- [ ] Implement process scanning from `/bin/ps`.
- [ ] Implement listening port parsing from `/usr/sbin/lsof`.
- [ ] Implement process tree construction and classifier integration.
- [ ] Implement signal delivery for stop and kill.
- [ ] Run `swift test`; expected result is all unit tests passing.

### Task 5: Menu Bar UI

- [ ] Implement `NSStatusItem` and `NSPopover` in `main.swift`.
- [ ] Implement observable process store.
- [ ] Build SwiftUI popover matching the approved Chinese mockup: title, summary, source/project segmented control, search, tree list, safety labels, and bottom action bar.
- [ ] Run `swift build`; expected result is a successful build.

### Task 6: Manual App Verification

- [ ] Run `swift run KillTool`.
- [ ] Confirm the menu bar icon appears without a Dock icon.
- [ ] Open the popover and verify Chinese UI appears.
- [ ] Verify Codex/Claude Code/VS Code/Terminal source labels on currently running development processes.
- [ ] Verify selected process actions are disabled when nothing is selected.

