import AppKit
import SwiftUI

@MainActor
final class KeyTallyAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminationPending = false
    private var didReply = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.start() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true

        Task { @MainActor in
            await model.shutdown()
            self.finishTermination(sender)
        }

        // Safety net if flush/stop hangs so Quit never gets stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.finishTermination(sender)
        }

        return .terminateLater
    }

    private func finishTermination(_ sender: NSApplication) {
        guard !didReply else { return }
        didReply = true
        sender.reply(toApplicationShouldTerminate: true)
    }
}

@main
struct KeyTallyApp: App {
    @NSApplicationDelegateAdaptor(KeyTallyAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: appDelegate.model)
        } label: {
            Label("KeyTally", systemImage: appDelegate.model.statusSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("KeyTally Dashboard", id: "dashboard") {
            DashboardView(model: appDelegate.model)
        }
        .defaultSize(width: 980, height: 720)
    }
}
