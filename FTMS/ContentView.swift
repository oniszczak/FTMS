//
//  ContentView.swift
//  FTMS Buddy
//
//  Created by ALEKSANDER ONISZCZAK on 2026-03-05.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var ftmsManager = FTMSManager()

    private var isDeviceConnected: Bool {
        ftmsManager.connectionState.hasPrefix("Connected to") && ftmsManager.connectedDeviceName != nil
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
            let maxFloatDistance = geometry.size.height * 0.55
            let floatOffset = -maxFloatDistance * floatProgress

            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.20), Color.cyan.opacity(0.10), Color.white.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 6) {
                    Text("Lift-Off Tracker")
                        .font(.headline)
                    Text("Units: \(ftmsManager.activityUnits)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
                .frame(maxHeight: .infinity, alignment: .top)

                ZStack {
                    houseShape

                    ForEach(0..<5, id: \.self) { balloonIndex in
                        balloonView(progress: balloonProgress(for: balloonIndex))
                            .offset(balloonOffset(for: balloonIndex))
                    }

                    ForEach(0..<5, id: \.self) { stringIndex in
                        balloonString(for: stringIndex)
                            .stroke(Color.secondary.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .offset(y: floatOffset)
                .animation(.easeInOut(duration: 0.35), value: ftmsManager.activityUnits)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var floatProgress: CGFloat {
        let extraUnits = max(0, ftmsManager.activityUnits - 60)
        return min(CGFloat(extraUnits) / 40.0, 1.0)
    }

    private func balloonProgress(for index: Int) -> CGFloat {
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
        let progressed = ftmsManager.activityUnits - range.start + 1
        return min(max(CGFloat(progressed) / CGFloat(span), 0), 1)
    }

    private func balloonOffset(for index: Int) -> CGSize {
        let xOffsets: [CGFloat] = [-96, -48, 0, 48, 96]
        let yOffsets: [CGFloat] = [-178, -198, -212, -198, -178]
        return CGSize(width: xOffsets[index], height: yOffsets[index])
    }

    private func balloonString(for index: Int) -> Path {
        let anchorX: [CGFloat] = [-65, -32, 0, 32, 65]
        let balloonPoint = balloonOffset(for: index)

        return Path { path in
            path.move(to: CGPoint(x: anchorX[index], y: -38))
            path.addQuadCurve(
                to: CGPoint(x: balloonPoint.width, y: balloonPoint.height + 30),
                control: CGPoint(x: (anchorX[index] + balloonPoint.width) * 0.55, y: balloonPoint.height * 0.45)
            )
        }
    }

    private var houseShape: some View {
        ZStack {
            Rectangle()
                .fill(Color.brown.opacity(0.9))
                .frame(width: 170, height: 115)
                .offset(y: 36)

            Path { path in
                path.move(to: CGPoint(x: -95, y: -20))
                path.addLine(to: CGPoint(x: 0, y: -95))
                path.addLine(to: CGPoint(x: 95, y: -20))
                path.closeSubpath()
            }
            .fill(Color.red.opacity(0.9))

            Rectangle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 34, height: 52)
                .offset(y: 58)

            Circle()
                .fill(Color.yellow.opacity(0.85))
                .frame(width: 24, height: 24)
                .offset(x: -52, y: 28)

            Circle()
                .fill(Color.yellow.opacity(0.85))
                .frame(width: 24, height: 24)
                .offset(x: 52, y: 28)
        }
    }

    private func balloonView(progress: CGFloat) -> some View {
        let clamped = min(max(progress, 0), 1)
        let size = 18 + (clamped * 44)

        return ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.pink.opacity(0.85), Color.purple.opacity(0.75)],
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

#Preview {
    ContentView()
}
