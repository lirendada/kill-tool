import AppKit
import KillToolCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store = ProcessStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: "开发进程")
            button.imagePosition = .imageOnly
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 520, height: 680)
        popover.contentViewController = NSHostingController(
            rootView: ProcessDashboardView(store: store)
        )
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            store.stopAutoRefresh()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
            }
            store.startAutoRefresh()
            store.refresh()
        }
    }

    private func showContextMenu(from sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            store.stopAutoRefresh()
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let quitItem = NSMenuItem(
            title: "退出 KillTool",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        menu.popUp(
            positioning: quitItem,
            at: NSPoint(x: 0, y: sender.bounds.height + 2),
            in: sender
        )
    }

    @objc private func quitApp(_ sender: Any?) {
        store.stopAutoRefresh()
        NSApp.terminate(nil)
    }
}

@main
enum KillToolMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
