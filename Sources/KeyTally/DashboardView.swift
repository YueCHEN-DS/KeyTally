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
                Text(model.todayTotals.headline.formatted())
                    .font(.title3.monospacedDigit().bold())
            }
            kindSplitRow(label: "  Keyboard", value: model.todayTotals.keyboard)
            kindSplitRow(label: "  Mouse", value: model.todayTotals.mouseClicks)

            HStack {
                Text("Lifetime")
                Spacer()
                Text(model.lifetimeSplit.headline.formatted())
                    .font(.title3.monospacedDigit().bold())
            }
            kindSplitRow(label: "  Keyboard", value: model.lifetimeSplit.keyboard)
            kindSplitRow(label: "  Mouse", value: model.lifetimeSplit.mouseClicks)

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
                if model.permissionState == .granted {
                    Text("If Settings already shows KeyTally on, toggle it off and on — each rebuild needs a fresh grant.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func kindSplitRow(label: String, value: UInt64) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var renameText = ""
    @State private var showingResetConfirmation = false
    @State private var exportError: String?
    @State private var showAllHistory = false

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
                    if model.isSelectedDeviceMouse {
                        MouseHeatmapView(counts: model.selectedCounts, title: mouseTitle)
                    } else if let selectedID = model.selectedKeyboardID,
                              model.keyboards[selectedID]?.isMouseDevice == false {
                        KeyboardHeatmapView(counts: model.selectedKeyboardCounts, title: heatmapTitle)
                        otherKeys
                    } else {
                        KeyboardHeatmapView(counts: model.selectedKeyboardCounts, title: heatmapTitle)
                        if model.hasMouseActivity {
                            MouseHeatmapView(counts: model.selectedMouseCounts, title: mouseTitle)
                        }
                        otherKeys
                    }
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
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.isRecording ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: model.statusSymbol)
                    .font(.headline)
                    .foregroundStyle(model.isRecording ? Color.green : Color.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
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
                    Text("\(model.connectedKeyboardIDs.count) input device(s) currently active")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var permissionGuidance: String {
        if model.permissionState == .granted {
            return "macOS reports permission granted, but CoreHID has not exposed keyboard elements yet. KeyTally is retrying automatically."
        }
        return "Enable the current KeyTally build in Input Monitoring. An ad-hoc rebuild must be authorized again. KeyTally rechecks automatically."
    }

    private var heatmapTitle: String {
        if model.isAllTime {
            return "US keyboard heatmap (Total Aggregated)"
        }
        return "US keyboard heatmap (\(model.selectedDate == model.today ? "Today" : model.selectedDate))"
    }

    private var mouseTitle: String {
        if model.isAllTime {
            return "Mouse activity (Total Aggregated)"
        }
        return "Mouse activity (\(model.selectedDate == model.today ? "Today" : model.selectedDate))"
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Day", selection: Binding(
                get: { model.selectedDate },
                set: {
                    model.selectedDate = $0
                    model.isAllTime = false
                }
            )) {
                ForEach(model.availableDates, id: \.self) { date in
                    Text(date == model.today ? "Today — \(date)" : date).tag(date)
                }
            }
            .frame(maxWidth: 260)
            .opacity(model.isAllTime ? 0.6 : 1.0)

            if model.isAllTime {
                Button {
                    model.isAllTime = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                        Text("Showing Total Aggregated")
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    model.isAllTime = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                        Text("Total Aggregated Usage")
                    }
                }
                .buttonStyle(.bordered)
            }

            Picker("Device", selection: $model.selectedKeyboardID) {
                Text("All devices").tag(String?.none)
                ForEach(model.sortedKeyboards) { device in
                    Label {
                        HStack {
                            Text(device.displayName)
                            if model.connectedKeyboardIDs.contains(device.id) {
                                Text("•")
                            }
                        }
                    } icon: {
                        Image(systemName: device.isMouseDevice ? "computermouse" : "keyboard")
                    }
                    .tag(Optional(device.id))
                }
            }
            .frame(maxWidth: 320)
            Spacer()
        }
    }

    private var summary: some View {
        let dayTotals = model.isAllTime ? model.selectedLifetimeTotals : model.selectedTotals
        let lifetime = model.selectedLifetimeTotals
        let dayTitle = model.isAllTime
            ? "All-Time"
            : (model.selectedDate == model.today ? "Today" : model.selectedDate)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                totalCard(
                    title: "\(dayTitle) Keyboard",
                    value: dayTotals.keyboard,
                    isActive: true,
                    icon: "keyboard"
                )
                totalCard(
                    title: "\(dayTitle) Mouse",
                    value: dayTotals.mouseClicks,
                    isActive: false,
                    icon: "computermouse"
                )
                Spacer()
            }
            if !model.isAllTime {
                HStack(spacing: 16) {
                    Button {
                        model.isAllTime = true
                    } label: {
                        totalCard(
                            title: "Lifetime Keyboard",
                            value: lifetime.keyboard,
                            isActive: false,
                            icon: "keyboard"
                        )
                    }
                    .buttonStyle(.plain)
                    Button {
                        model.isAllTime = true
                    } label: {
                        totalCard(
                            title: "Lifetime Mouse",
                            value: lifetime.mouseClicks,
                            isActive: false,
                            icon: "computermouse"
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            Text("Wheel scroll appears in the mouse panel only — not in these totals.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func totalCard(
        title: String,
        value: UInt64,
        isActive: Bool = false,
        icon: String = "number"
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(value.formatted())
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("physical inputs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 230, alignment: .leading)
        .padding(16)
        .background(
            isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dailyHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily history").font(.headline)
                Spacer()
                if model.selectedDailyHistory.count > 3 {
                    Button(showAllHistory ? "Show recent 3 days" : "Show all (\(model.selectedDailyHistory.count) days)") {
                        showAllHistory.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }

            if model.selectedDailyHistory.isEmpty {
                Text("No recorded days yet.")
                    .foregroundStyle(.secondary)
            } else {
                let displayedDays = showAllHistory
                    ? model.selectedDailyHistory
                    : Array(model.selectedDailyHistory.prefix(3))
                LazyVStack(spacing: 6) {
                    ForEach(displayedDays) { day in
                        Button {
                            model.selectedDate = day.date
                            model.isAllTime = false
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
                                (!model.isAllTime && day.date == model.selectedDate)
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
    var title: String = "US keyboard heatmap"

    private var maximum: UInt64 {
        max(counts.values.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
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

struct MouseHeatmapView: View {
    let counts: [String: UInt64]
    var title: String = "Mouse activity"

    private var leftCount: UInt64 {
        counts[KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseLeftButton).storageKey, default: 0]
    }

    private var rightCount: UInt64 {
        counts[KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseRightButton).storageKey, default: 0]
    }

    private var wheelClickCount: UInt64 {
        counts[KeyID(usagePage: KeyCatalog.buttonPage, usageID: KeyCatalog.mouseMiddleButton).storageKey, default: 0]
    }

    private var wheelScrollCount: UInt64 {
        counts[KeyID(usagePage: KeyCatalog.genericDesktopPage, usageID: KeyCatalog.mouseWheelScroll).storageKey, default: 0]
    }

    private var wheelTotal: UInt64 {
        wheelClickCount + wheelScrollCount
    }

    private var maximum: UInt64 {
        max(leftCount, rightCount, wheelTotal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "computermouse.fill")
                    .font(.headline)
                Spacer()
                Text("Left, Right & Wheel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                mouseSilhouette
                    .frame(width: 140, height: 210)
                    .padding(.vertical, 6)

                VStack(spacing: 8) {
                    mouseMetricRow(
                        title: "Left Button",
                        subtitle: "Primary click",
                        count: leftCount,
                        icon: "computermouse"
                    )
                    mouseMetricRow(
                        title: "Scroll Wheel",
                        subtitle: "\(wheelClickCount.formatted()) clicks • \(wheelScrollCount.formatted()) scrolls",
                        count: wheelTotal,
                        icon: "circle.grid.cross"
                    )
                    mouseMetricRow(
                        title: "Right Button",
                        subtitle: "Secondary click",
                        count: rightCount,
                        icon: "computermouse"
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding(18)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.secondary.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    private var mouseSilhouette: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let buttonH = h * 0.44

            ZStack {
                // Outer mouse body
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .stroke(.secondary.opacity(0.3), lineWidth: 1.5)
                    )

                // Top buttons
                VStack(spacing: 0) {
                    HStack(spacing: 1.5) {
                        buttonSector(count: leftCount, label: "Left")
                        buttonSector(count: rightCount, label: "Right")
                    }
                    .frame(height: buttonH)

                    Spacer()

                    // Palm rest area
                    VStack(spacing: 4) {
                        Image(systemName: "computermouse.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .opacity(0.4)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))

                // Center Scroll Wheel
                VStack {
                    Capsule()
                        .fill(
                            Color.accentColor.opacity(
                                wheelTotal == 0 ? 0.12 : 0.25 + 0.65 * sqrt(Double(wheelTotal) / Double(maximum))
                            )
                        )
                        .frame(width: 20, height: 42)
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 1)
                        )
                        .overlay(
                            VStack(spacing: 2) {
                                ForEach(0..<3) { _ in
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.25))
                                        .frame(width: 8, height: 1.5)
                                }
                            }
                        )
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        .padding(.top, buttonH * 0.28)
                    Spacer()
                }
            }
        }
    }

    private func buttonSector(count: UInt64, label: String) -> some View {
        let intensity = count == 0 ? 0 : sqrt(Double(count) / Double(maximum))

        return ZStack {
            Rectangle()
                .fill(Color.accentColor.opacity(count == 0 ? 0.04 : 0.15 + 0.70 * intensity))
            VStack(spacing: 3) {
                Text(label)
                    .font(.caption2.bold())
                Text(count.formatted())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mouseMetricRow(
        title: String,
        subtitle: String,
        count: UInt64,
        icon: String
    ) -> some View {
        let intensity = count == 0 ? 0 : sqrt(Double(count) / Double(maximum))

        return HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(count == 0 ? 0.08 : 0.2 + 0.7 * intensity))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(count == 0 ? .secondary : Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(count.formatted())
                .font(.title3.monospacedDigit().bold())
            Text("inputs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
