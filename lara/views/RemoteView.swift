//
//  RemoteView.swift
//  lara
//
//  Created by ruter on 17.04.26.
//

import SwiftUI

struct RemoteView: View {
    @ObservedObject var mgr: laramgr
    @State private var isRunning: Bool = false
    @State private var dockColumns: Int = 5
    @AppStorage("rcDockUnlimited") private var rcDockUnlimited: Bool = false

    private var dockMaxColumns: Int { rcDockUnlimited ? 50 : 10 }

    var body: some View {
        List {
            Section {
                if !mgr.remotecallrunning {
                    Text("RemoteCall is not initialized.")
                        .foregroundColor(.secondary)
                }

                Button {
                    run("Status Bar Time Format") {
                        status_bar_tweak(mgr.sbProc)
                        return "status_bar_tweak() done"
                    }
                } label: {
                    Text("Status Bar Time Format")
                }
                .disabled(!mgr.remotecallrunning || isRunning)

                Button {
                    run("Hide Icon Labels") {
                        let hidden = hide_icon_labels(mgr.sbProc)
                        return "hide_icon_labels() -> \(hidden)"
                    }
                } label: {
                    Text("Hide Icon Labels")
                }
                .disabled(!mgr.remotecallrunning || isRunning)

                Stepper(value: $dockColumns, in: 1...dockMaxColumns) {
                    HStack {
                        Text("Dock columns")
                        Spacer()
                        Text("\(dockColumns)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .disabled(!mgr.remotecallrunning || isRunning)
                .onChange(of: rcDockUnlimited) { _ in
                    if !rcDockUnlimited, dockColumns > 10 {
                        dockColumns = 10
                    }
                }

                Button {
                    run("Apply Dock Columns=\(dockColumns)") {
                        let result = set_dock_icon_count(mgr.sbProc, Int32(dockColumns))
                        return "set_dock_icon_count(\(dockColumns)) -> \(result)"
                    }
                } label: {
                    Text("Apply Dock Columns")
                }
                .disabled(!mgr.remotecallrunning || isRunning)

                Button {
                    run("Enable Upside Down") {
                        let result = enable_upside_down(mgr.sbProc)
                        return "enable_upside_down() -> \(result)"
                    }
                } label: {
                    Text("Enable Upside Down")
                }
                .disabled(!mgr.remotecallrunning || isRunning)
            } header: {
                Text("SpringBoard")
            } footer: {
                Text("These call into SpringBoard via RemoteCall. Keep RemoteCall initialized while running them.")
            }
        }
        .navigationTitle(Text("Tweaks"))
    }

    private func run(_ name: String, _ work: @escaping () -> String) {
        guard mgr.remotecallrunning, !isRunning else { return }
        isRunning = true
        mgr.logmsg("(rc) \(name)...")

        DispatchQueue.global(qos: .userInitiated).async {
            let result = work()
            DispatchQueue.main.async {
                self.mgr.logmsg("(rc) \(result)")
                self.isRunning = false
            }
        }
    }
}
