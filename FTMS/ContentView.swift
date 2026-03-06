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
        VStack {
            Text("Animation Pane")
                .font(.title3.weight(.semibold))
            Text("Ready for metric-driven animation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ContentView()
}
