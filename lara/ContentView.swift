//
//  ContentView.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import SwiftUI
import notify

struct ContentView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var uid: uid_t = getuid()
    @State private var pid: pid_t = getpid()
    @State private var hasoffsets = haskernproc()
    @State private var showresetalert = false
    @State private var showfontsheet = false
    
    var body: some View {
        NavigationStack {
            List {
                if !hasoffsets {
                    Section("Kernelcache") {
                        Button("Download Kernelcache") {
                            DispatchQueue.global(qos: .userInitiated).async {
                                let ok = dlkerncache()
                                DispatchQueue.main.async {
                                    hasoffsets = ok
                                }
                            }
                        }
                    }
                } else {
                    Section("Kernel Read Write") {
                        Button(mgr.dsrunning ? "Running..." : "Run Exploit") {
                            mgr.run()
                        }
                        .disabled(mgr.dsrunning)
                        .disabled(mgr.dsready)
                        
                        HStack {
                            Text("krw ready?")
                            Spacer()
                            Text(mgr.dsready ? "Yes" : "No")
                                .foregroundColor(mgr.dsready ? .green : .red)
                        }
                        
                        HStack {
                            Text("kernproc:")
                            Spacer()
                            Text(String(format: "0x%llx", getkernproc()))
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        if mgr.dsready {
                            HStack {
                                Text("kernel_base:")
                                Spacer()
                                Text(String(format: "0x%llx", mgr.kernbase))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text("kernel_slide:")
                                Spacer()
                                Text(String(format: "0x%llx", mgr.kernslide))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section("Kernel File System (broken)") {
                        Button("Initialize KFS") {
                            mgr.kfsinit()
                        }
                        .disabled(!mgr.dsready)
                        
                        Button("Font Overwrite") {
                            showfontsheet = true
                        }
                        .disabled(!mgr.kfsready)
                        .confirmationDialog("Set System Font", isPresented: $showfontsheet, titleVisibility: .visible) {
                            Button("Comic Sans MS") {
                                let success = mgr.kfsoverwrite(target: laramgr.fontpath, withBundledFont: "Comic Sans MS")
                                
                                if success {
                                    mgr.logmsg("font changed to Comic Sans MS")
                                } else {
                                    mgr.logmsg("failed to change font")
                                }
                            }
                            
                            Button("SFUI (Normal Font)") {
                                let success = mgr.kfsoverwrite(target: laramgr.fontpath, withBundledFont: "SFUI")
                                
                                if success {
                                    mgr.logmsg("font changed to SFUI")
                                } else {
                                    mgr.logmsg("failed to change font")
                                }
                            }
                            
                            Button("Cancel", role: .cancel) { }
                        }
                        
                        HStack {
                            Text("UID:")
                            
                            Spacer()
                            
                            Text("\(uid)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Button {
                                uid = getuid()
                                print(uid)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        
                        HStack {
                            Text("PID:")
                            
                            Spacer()
                            
                            Text("\(pid)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Button {
                                pid = getpid()
                                print(pid)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                    
                    Section {
                        Button("Respring") {
                            notify_post("com.apple.springboard.toggleLockScreen")
                        }
                        
                        Button("Panic!") {
                            mgr.panic()
                        }
                        .disabled(!mgr.dsready)
                    } header: {
                        Text("Other")
                    }
                }
                
                Section {
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/rooootdev.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("roooot")
                                .font(.headline)
                            
                            Text("Main Developer")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/rooootdev"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    HStack(alignment: .top) {
                        AsyncImage(url: URL(string: "https://github.com/AppInstalleriOSGH.png")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("AppInstaller iOS")
                                .font(.headline)
                            
                            Text("Helped me with offsets and other stuff. This project wouldnt have been possible without him!")
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                    }
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/khanhduytran0"),
                           UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    }
                } header: {
                    Text("Credits")
                }
            }
            .navigationTitle("lara")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showresetalert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert("Clear Kernelcache Data?", isPresented: $showresetalert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                clearkerncachedata()
                hasoffsets = haskernproc()
            }
        } message: {
            Text("This will delete the downloaded kernelcache and remove saved offsets.")
        }
    }
}
