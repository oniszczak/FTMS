//
//  ContentView.swift
//  FTMS Buddy
//
//  Created by ALEKSANDER ONISZCZAK on 2026-03-05.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var ftmsManager = FTMSManager()

    @State private var animationPhase: LiftOffPhase = .inflating
    @State private var consumedUnits = 0
    @State private var liftProgress: CGFloat = 0
    @State private var cycleToken = UUID()
    @State private var unitAnimationToken = UUID()
    @State private var animatedActivityUnits = 0
    @State private var completedTakeoffs = 0
    @State private var housePalette = HousePalette.random()
    @State private var balloonColors = (0..<5).map { _ in BalloonPalette.random() }

    private var isDeviceConnected: Bool {
        ftmsManager.connectionState.hasPrefix("Connected to") && ftmsManager.connectedDeviceName != nil
    }

    private var unitsInCurrentCycle: Int {
        max(0, animatedActivityUnits - consumedUnits)
    }

    private static let paneColorSteps: [Color] = [.yellow, .red, .green, .purple, .black, .white, .blue]

    private static let paneDarkTextIndexes: Set<Int> = [0, 2, 5]

    private var paneColorIndex: Int {
        (completedTakeoffs / 3) % Self.paneColorSteps.count
    }

    private var paneBackgroundColor: Color {
        Self.paneColorSteps[paneColorIndex]
    }

    private var paneForegroundColor: Color {
        Self.paneDarkTextIndexes.contains(paneColorIndex) ? .black : .white
    }

    var body: some View {
        Group {
            if isDeviceConnected {
                connectedDashboard
            } else {
                setupView
            }
        }
        .onAppear {
            ftmsManager.startScan()
        }
        .onChange(of: ftmsManager.activityUnits) { _, _ in
            syncAnimatedUnits()
        }
        .onChange(of: isDeviceConnected) { _, isConnected in
            if !isConnected {
                resetAnimationState()
            } else {
                syncAnimatedUnits()
            }
        }
    }

    private var setupView: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    LabeledContent("State", value: ftmsManager.bluetoothState)
                    LabeledContent("Connection", value: ftmsManager.connectionState)

                    if let error = ftmsManager.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Button(ftmsManager.isScanning ? "Stop Scan" : "Scan for Devices") {
                        if ftmsManager.isScanning {
                            ftmsManager.stopScan()
                        } else {
                            ftmsManager.startScan()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section("Available Devices") {
                    if ftmsManager.discoveredDevices.isEmpty {
                        Text("No FTMS/CSC devices discovered yet. Start a scan and power on your equipment.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ftmsManager.discoveredDevices) { device in
                            Button {
                                ftmsManager.connect(to: device)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name)
                                            .font(.headline)
                                        Text(device.id.uuidString)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("RSSI \(device.rssi)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if device.advertisesFTMS {
                                            Text("FTMS")
                                                .font(.caption2)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.green.opacity(0.2), in: Capsule())
                                        }

                                        if device.advertisesCSC {
                                            Text("CSC")
                                                .font(.caption2)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.blue.opacity(0.2), in: Capsule())
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Gym Machine Buddy")
        }
    }

    private var connectedDashboard: some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height >= geometry.size.width

            Group {
                if isPortrait {
                    VStack(spacing: 12) {
                        metricsPane
                        animationPane
                    }
                } else {
                    HStack(spacing: 12) {
                        metricsPane
                        animationPane
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var metricsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ftmsManager.connectedDeviceName ?? "Connected Device")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("Disconnect", role: .destructive) {
                    ftmsManager.disconnect()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .font(.subheadline.weight(.semibold))
            }

            Divider()

            if ftmsManager.metrics.isEmpty {
                Text("Waiting for live metrics...")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(ftmsManager.metrics) { metric in
                            HStack {
                                Text(metric.name)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(metric.value)
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var animationPane: some View {
        GeometryReader { geometry in
            let sceneSize = CGSize(width: 320, height: 360)
            let maxFloatDistance = geometry.size.height + sceneSize.height
            let floatOffset = -maxFloatDistance * liftProgress

            ZStack {
                paneBackgroundColor

                if animationPhase == .celebrating {
                    Text("You did it!")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(paneForegroundColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        Text("Units: \(animatedActivityUnits)")
                            .font(.subheadline)
                            .foregroundStyle(paneForegroundColor.opacity(0.85))
                    }
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity, alignment: .top)

                    ZStack {
                        houseShape
                            .offset(y: 70)

                        ForEach(0..<5, id: \.self) { stringIndex in
                            balloonString(for: stringIndex, in: sceneSize)
                                .stroke(Color.black.opacity(0.45), lineWidth: 1.8)
                        }

                        ForEach(0..<5, id: \.self) { balloonIndex in
                            balloonView(
                                progress: balloonProgress(for: balloonIndex),
                                palette: balloonColors[balloonIndex]
                            )
                            .offset(balloonOffset(for: balloonIndex))
                        }
                    }
                    .frame(width: sceneSize.width, height: sceneSize.height)
                    .offset(y: floatOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .animation(.linear(duration: 2.0), value: liftProgress)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func updateAnimationStateIfNeeded() {
        guard isDeviceConnected else { return }
        guard animationPhase == .inflating else { return }

        if unitsInCurrentCycle >= 60 {
            startLiftOffSequence()
        }
    }

    private func syncAnimatedUnits() {
        guard isDeviceConnected else { return }

        let targetUnits = ftmsManager.activityUnits

        if targetUnits <= animatedActivityUnits {
            unitAnimationToken = UUID()
            animatedActivityUnits = targetUnits
            updateAnimationStateIfNeeded()
            return
        }

        let token = UUID()
        unitAnimationToken = token

        Task { @MainActor in
            while unitAnimationToken == token,
                  isDeviceConnected,
                  animatedActivityUnits < targetUnits {
                animatedActivityUnits += 1
                updateAnimationStateIfNeeded()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func startLiftOffSequence() {
        animationPhase = .lifting
        consumedUnits += 60

        let token = UUID()
        cycleToken = token

        withAnimation(.linear(duration: 2.0)) {
            liftProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard cycleToken == token, isDeviceConnected else { return }

            animationPhase = .celebrating

            try? await Task.sleep(for: .seconds(2))
            guard cycleToken == token, isDeviceConnected else { return }

            completedTakeoffs += 1
            randomizeVisualsForNextCycle()
            liftProgress = 0
            animationPhase = .inflating
            updateAnimationStateIfNeeded()
        }
    }

    private func resetAnimationState() {
        cycleToken = UUID()
        unitAnimationToken = UUID()
        consumedUnits = 0
        animatedActivityUnits = 0
        completedTakeoffs = 0
        liftProgress = 0
        animationPhase = .inflating
        randomizeVisualsForNextCycle()
    }

    private func randomizeVisualsForNextCycle() {
        housePalette = HousePalette.random()
        balloonColors = (0..<5).map { _ in BalloonPalette.random() }
    }

    private func balloonProgress(for index: Int) -> CGFloat {
        if animationPhase != .inflating {
            return 1
        }

        // Requested ranges: 1-10, 11-20, 21-40, 41-50, 51-60
        let ranges: [(start: Int, end: Int)] = [
            (1, 10),
            (11, 20),
            (21, 40),
            (41, 50),
            (51, 60)
        ]

        let range = ranges[index]
        let span = max(1, range.end - range.start + 1)
        let progressed = min(unitsInCurrentCycle, 60) - range.start + 1
        return min(max(CGFloat(progressed) / CGFloat(span), 0), 1)
    }

    private func balloonOffset(for index: Int) -> CGSize {
        let xOffsets: [CGFloat] = [-102, -52, 0, 52, 102]
        let yOffsets: [CGFloat] = [-132, -158, -174, -158, -132]
        return CGSize(width: xOffsets[index], height: yOffsets[index])
    }

    private func balloonString(for index: Int, in sceneSize: CGSize) -> Path {
        let center = CGPoint(x: sceneSize.width / 2.0, y: sceneSize.height / 2.0)
        let anchorX: [CGFloat] = [-86, -44, 0, 44, 86]
        let start = CGPoint(x: center.x + anchorX[index], y: center.y + 58)
        let balloonPoint = balloonOffset(for: index)
        let balloonSize = 18 + (balloonProgress(for: index) * 44)
        let end = CGPoint(
            x: center.x + balloonPoint.width,
            y: center.y + balloonPoint.height + (balloonSize * 0.62)
        )

        return Path { path in
            path.move(to: start)
            path.addQuadCurve(
                to: end,
                control: CGPoint(x: (start.x + end.x) * 0.5, y: min(start.y, end.y) - 18)
            )
        }
    }

    private var houseShape: some View {
        ZStack {
            Rectangle()
                .fill(housePalette.body)
                .frame(width: 170, height: 115)
                .offset(y: 34)

            Triangle()
                .fill(housePalette.roof)
                .frame(width: 210, height: 92)
                .offset(y: -54)
                .overlay {
                    Triangle()
                        .stroke(Color.black.opacity(0.22), lineWidth: 2)
                        .frame(width: 210, height: 92)
                        .offset(y: -54)
                }

            Rectangle()
                .fill(housePalette.door)
                .frame(width: 34, height: 52)
                .offset(y: 56)

            Circle()
                .fill(housePalette.window)
                .frame(width: 24, height: 24)
                .offset(x: -52, y: 26)

            Circle()
                .fill(housePalette.window)
                .frame(width: 24, height: 24)
                .offset(x: 52, y: 26)
        }
        .frame(width: 220, height: 220)
    }

    private func balloonView(progress: CGFloat, palette: BalloonPalette) -> some View {
        let clamped = min(max(progress, 0), 1)
        let size = 18 + (clamped * 44)

        return ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [palette.top.opacity(0.9), palette.bottom.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size * 1.25)
                .opacity(0.25 + (0.75 * clamped))

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: -size * 0.16, y: -size * 0.25)
        }
    }
}

private enum LiftOffPhase {
    case inflating
    case lifting
    case celebrating
}

private struct HousePalette {
    let body: Color
    let roof: Color
    let door: Color
    let window: Color

    static func random() -> HousePalette {
        let bodyColors: [Color] = [.brown, .orange, .mint, .teal, .indigo, .cyan]
        let roofColors: [Color] = [.red, .pink, .purple, .blue, .green]
        let doorColors: [Color] = [.white, .gray, .black.opacity(0.7), .yellow.opacity(0.9)]
        let windowColors: [Color] = [.yellow.opacity(0.85), .white.opacity(0.9), .cyan.opacity(0.9)]

        return HousePalette(
            body: bodyColors.randomElement() ?? .brown,
            roof: roofColors.randomElement() ?? .red,
            door: doorColors.randomElement() ?? .white,
            window: windowColors.randomElement() ?? .yellow.opacity(0.85)
        )
    }
}

private struct BalloonPalette {
    let top: Color
    let bottom: Color

    static func random() -> BalloonPalette {
        let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink]
        let top = colors.randomElement() ?? .pink
        let bottom = colors.randomElement() ?? .purple
        return BalloonPalette(top: top, bottom: bottom)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ContentView()
}
