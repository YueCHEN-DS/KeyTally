import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.statusText, systemImage: model.statusSymbol)
                .font(.headline)
                .foregroundStyle(model.isRecording ? .primary : .secondary)

            HStack {
                Text("Today")
                Spacer()
                Text(model.todayTotal.formatted())
                    .font(.title3.monospacedDigit().bold())
            }

            HStack {
                Text("Lifetime")
                Spacer()
                Text(model.lifetimeTotal.formatted())
                    .font(.title3.monospacedDigit().bold())
            }

            Divider()

            if !model.hasInputAccess {
                Button("Request Input Monitoring") {
                    model.requestInputMonitoring()
                }
                Button("Open Input Monitoring Settings") {
                    model.openInputMonitoringSettings()
                }
                Button("Recheck Keyboard Access") {
                    model.recheckInputMonitoring()
                }
            } else {
                Button(model.isPaused ? "Resume Counting" : "Pause Counting") {
                    model.togglePause()
                }
            }

            Button("Open Dashboard") {
                openWindow(id: "dashboard")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("d")

            Divider()

            Button("Quit KeyTally") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 300)
        .task { await model.start() }
    }
}

struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var renameText = ""
    @State private var showingResetConfirmation = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusCard
                    controls
                    summary
                    dailyHistory
                    KeyboardHeatmapView(counts: model.selectedCounts)
                    otherKeys
                    deviceRename
                    privacyNote
                }
                .padding(24)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .task { await model.start() }
        .onAppear { syncRenameText() }
        .onChange(of: model.selectedKeyboardID) { _, _ in syncRenameText() }
        .confirmationDialog(
            "Reset all key counts?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Counts", role: .destructive) {
                Task { await model.resetCounts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keyboard names are preserved. Daily counts cannot be recovered.")
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("KeyTally")
                    .font(.largeTitle.bold())
                Text("Local physical-keyboard counts")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.isPaused ? "Resume" : "Pause") {
                model.togglePause()
            }
            .disabled(!model.hasInputAccess || model.storageError != nil)

            Button("Export CSV") { exportCSV() }
            Button("Reset", role: .destructive) { showingResetConfirmation = true }
        }
        .padding(20)
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.statusSymbol)
                .font(.title2)
                .foregroundStyle(model.isRecording ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.statusText).font(.headline)
                if !model.hasInputAccess {
                    Text(permissionGuidance)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Request Permission") { model.requestInputMonitoring() }
                        Button("Open System Settings") { model.openInputMonitoringSettings() }
                        Button("Recheck Access") { model.recheckInputMonitoring() }
                    }
                } else {
                    Text("\(model.connectedKeyboardIDs.count) keyboard(s) currently connected")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var permissionGuidance: String {
        if model.permissionState == .granted {
            return "macOS reports permission granted, but CoreHID has not exposed keyboard elements yet. KeyTally is retrying automatically."
        }
        return "Enable the current KeyTally build in Input Monitoring. An ad-hoc rebuild must be authorized again. KeyTally rechecks automatically."
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Picker("Day", selection: $model.selectedDate) {
                ForEach(model.availableDates, id: \.self) { date in
                    Text(date == model.today ? "Today — \(date)" : date).tag(date)
                }
            }
            .frame(maxWidth: 260)

            Picker("Keyboard", selection: $model.selectedKeyboardID) {
                Text("All keyboards").tag(String?.none)
                ForEach(model.sortedKeyboards) { keyboard in
                    HStack {
                        Text(keyboard.displayName)
                        if model.connectedKeyboardIDs.contains(keyboard.id) {
                            Text("•")
                        }
                    }
                    .tag(Optional(keyboard.id))
                }
            }
            .frame(maxWidth: 320)
            Spacer()
        }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            totalCard(
                title: model.selectedDate == model.today ? "Today" : model.selectedDate,
                value: model.selectedTotal
            )
            totalCard(title: "Lifetime", value: model.selectedLifetimeTotal)
            Spacer()
        }
    }

    private func totalCard(title: String, value: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("physical presses")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 230, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var dailyHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily history").font(.headline)

            if model.selectedDailyHistory.isEmpty {
                Text("No recorded days yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(model.selectedDailyHistory) { day in
                        Button {
                            model.selectedDate = day.date
                        } label: {
                            HStack {
                                Text(day.date == model.today ? "Today — \(day.date)" : day.date)
                                Spacer()
                                Text(day.total.formatted())
                                    .monospacedDigit()
                                Text("presses")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                day.date == model.selectedDate
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var otherKeys: some View {
        let entries = KeyCatalog.nonHeatmapKeys.compactMap { definition -> (KeyDefinition, UInt64)? in
            guard let count = model.selectedCounts[definition.id], count > 0 else { return nil }
            return (definition, count)
        }

        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Other standard keys").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 8) {
                    ForEach(entries, id: \.0.id) { entry in
                        HStack {
                            Text(entry.0.label)
                            Spacer()
                            Text(entry.1.formatted()).monospacedDigit()
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var deviceRename: some View {
        if let selectedID = model.selectedKeyboardID,
           let keyboard = model.keyboards[selectedID] {
            VStack(alignment: .leading, spacing: 9) {
                Text("Keyboard name").font(.headline)
                HStack {
                    TextField(keyboard.reportedName, text: $renameText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Name") {
                        model.renameKeyboard(id: selectedID, to: renameText)
                    }
                    Button("Use Reported Name") {
                        renameText = ""
                        model.renameKeyboard(id: selectedID, to: "")
                    }
                }
                Text("Reported by CoreHID: \(keyboard.reportedName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacyNote: some View {
        Label(
            "Only daily aggregate counts are saved. Key order, typed characters, timestamps, apps, windows, and network data are never stored.",
            systemImage: "lock.shield.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func syncRenameText() {
        guard let selectedID = model.selectedKeyboardID,
              let keyboard = model.keyboards[selectedID] else {
            renameText = ""
            return
        }
        renameText = keyboard.customName ?? ""
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export KeyTally History"
        panel.nameFieldStringValue = "KeyTally-\(model.today).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(model.csvString().utf8).write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

struct KeyboardHeatmapView: View {
    let counts: [String: UInt64]

    private var maximum: UInt64 {
        max(counts.values.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("US keyboard heatmap").font(.headline)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(KeyCatalog.heatmapRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 5) {
                            ForEach(row) { key in
                                keyCap(key)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func keyCap(_ definition: KeyDefinition) -> some View {
        let count = counts[definition.id, default: 0]
        let intensity = count == 0 ? 0 : sqrt(Double(count) / Double(maximum))

        return VStack(spacing: 2) {
            Text(definition.label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(count.formatted())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 36 * definition.width, height: 40)
        .background(
            Color.accentColor.opacity(count == 0 ? 0.05 : 0.18 + 0.72 * intensity),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.secondary.opacity(0.22), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(definition.label), \(count) presses")
    }
}
