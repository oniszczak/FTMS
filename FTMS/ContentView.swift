//
//  ContentView.swift
//  FTMS Buddy
//
//  Created by ALEKSANDER ONISZCZAK on 2026-03-05.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var ftmsManager = FTMSManager()

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    LabeledContent("State", value: ftmsManager.bluetoothState)
                    LabeledContent("Connection", value: ftmsManager.connectionState)

                    if let connectedName = ftmsManager.connectedDeviceName {
                        LabeledContent("Connected Device", value: connectedName)
                    }

                    if let error = ftmsManager.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    HStack {
                        Button(ftmsManager.isScanning ? "Stop Scan" : "Scan for Devices") {
                            if ftmsManager.isScanning {
                                ftmsManager.stopScan()
                            } else {
                                ftmsManager.startScan()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if ftmsManager.connectedDeviceName != nil {
                            Button("Disconnect", role: .destructive) {
                                ftmsManager.disconnect()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Section("Available Devices") {
                    if ftmsManager.discoveredDevices.isEmpty {
                        Text("No devices discovered yet. Start a scan and power on your rower/bike.")
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

                Section("Live Metrics (FTMS / CSC)") {
                    if ftmsManager.metrics.isEmpty {
                        Text("Connect to a device and start exercising to see live cadence, speed, power, heart rate, and other FTMS/CSC values.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ftmsManager.metrics) { metric in
                            LabeledContent(metric.name, value: metric.value)
                        }
                    }
                }

            }
            .navigationTitle("Gym Machine Buddy")
            .onAppear {
                ftmsManager.startScan()
            }
        }
    }
}

#Preview {
    ContentView()
}
