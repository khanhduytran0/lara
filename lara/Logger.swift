//
//  Logger.swift
//  mowiwewgewawt
//  bacon why would you do that
//  teehee :3
//  yeah yeah teehee all you want 
//
//  Created by roooot on 15.11.25.
//

import Foundation
import Darwin
import Combine
import SwiftUI

let globallogger = Logger()

class Logger: ObservableObject {
    @Published var logs: [String] = []
    private var lastwasdivider = false
    private var pendingdivider = false
    private var stdoutpipe: Pipe?
    private var panding = ""
    private var ogstdout: Int32 = -1
    private var ogstderr: Int32 = -1

    init() {}

    func log(_ message: String) {
        DispatchQueue.main.async {
            if self.pendingdivider {
                self.divider()
                self.pendingdivider = false
            }
            
            if self.lastwasdivider || self.logs.isEmpty {
                self.logs.append(message)
            } else {
                self.logs[self.logs.count - 1] += "\n" + message
            }

            self.lastwasdivider = false
        }

        emit(message)
    }

    func divider() {
        DispatchQueue.main.async {
            self.lastwasdivider = true
        }
    }
    
    func enclosedlog(_ message: String) {
        DispatchQueue.main.async {
            if !self.lastwasdivider && !self.logs.isEmpty {
                self.divider()
            }
            
            if self.lastwasdivider || self.logs.isEmpty {
                self.logs.append(message)
            } else {
                self.logs[self.logs.count - 1] += "\n" + message
            }
            
            self.lastwasdivider = false
            self.pendingdivider = true
        }
    }
    
    func flushdivider() {
        DispatchQueue.main.async {
            if self.pendingdivider {
                self.divider()
                self.pendingdivider = false
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.lastwasdivider = false
            self.pendingdivider = false
        }
    }

    func capture() {
        if stdoutpipe != nil { return }

        let pipe = Pipe()
        stdoutpipe = pipe

        ogstdout = dup(STDOUT_FILENO)
        ogstderr = dup(STDERR_FILENO)

        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            self?.appendraw(chunk)
        }
    }

    private func appendraw(_ chunk: String) {
        var text = panding + chunk
        var lines = text.components(separatedBy: "\n")
        panding = lines.removeLast()
        if !lines.isEmpty {
            DispatchQueue.main.async {
                self.logs.append(contentsOf: lines)
            }
            for line in lines {
                emit(line)
            }
        }
    }

    private func emit(_ message: String) {
        guard ogstdout != -1 else { return }
        let line = message + "\n"
        line.withCString { ptr in
            _ = Darwin.write(ogstdout, ptr, strlen(ptr))
        }
    }
}

struct LogsView: View {
    @ObservedObject var logger: Logger

    var body: some View {
        NavigationView {
            List {
                ForEach(logger.logs, id: \.self) { log in
                    Text(log)
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(1)
                        .onTapGesture {
                            UIPasteboard.general.string = log
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    
                    Button {
                        let allLogs = logger.logs.joined(separator: "\n\n")
                        UIPasteboard.general.string = allLogs
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    
                    Button {
                        globallogger.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}
