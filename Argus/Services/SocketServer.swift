//
//  SocketServer.swift
//  Argus
//
//  Unix domain socket server for receiving agent events.
//

import Foundation

protocol SocketServerDelegate: AnyObject {
    func didReceive(event: AgentEventPayload)
}

struct AgentEventPayload: Codable {
    let sessionId: String?
    let agentType: String?
    let eventType: String
    let command: String?
    let workingDirectory: String?
    let message: String
    let timestamp: Date?
}

final class SocketServer: NSObject {
    weak var delegate: SocketServerDelegate?
    
    private var socketPath: String { "/tmp/argus.sock" }
    private var serverSocket: Int32 = -1
    private var socketSource: DispatchSourceRead?
    
    func start() {
        try? FileManager.default.removeItem(atPath: socketPath)
        
        serverSocket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("Failed to create socket")
            return
        }
        
        var value: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        strncpy(&addr.sun_path.0, socketPath, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sa_family_t>.size + strlen(socketPath) + 1))
            }
        }
        
        guard bindResult == 0 else {
            print("Failed to bind socket")
            Darwin.close(serverSocket)
            return
        }
        
        guard listen(serverSocket, 10) == 0 else {
            print("Failed to listen on socket")
            Darwin.close(serverSocket)
            return
        }
        
        let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: .global())
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.resume()
        socketSource = source
        
        print("Socket server listening at \(socketPath)")
    }
    
    func stop() {
        socketSource?.cancel()
        socketSource = nil
        if serverSocket >= 0 {
            Darwin.close(serverSocket)
            serverSocket = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }
    
    private func acceptConnection() {
        var addr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let client = withUnsafeMutablePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.accept(serverSocket, sockaddrPtr, &len)
            }
        }
        
        guard client >= 0 else { return }
        DispatchQueue.global().async { [weak self] in
            self?.handleClient(socket: client)
        }
    }
    
    private func handleClient(socket: Int32) {
        defer { Darwin.close(socket) }
        
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        while true {
            let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                Darwin.read(socket, ptr.baseAddress!, bufferSize)
            }
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }
        
        guard !data.isEmpty else { return }
        
        do {
            let payload = try JSONDecoder().decode(AgentEventPayload.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didReceive(event: payload)
            }
        } catch {
            if let str = String(data: data, encoding: .utf8) {
                print("Received non-JSON data: \(str)")
            }
        }
    }
}
