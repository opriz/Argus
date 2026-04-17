//
//  MenuBarController.swift
//  Argus
//

import SwiftUI
import AppKit
import Combine

final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var socketServer: SocketServer!
    private let discovery = ClaudeSessionDiscovery()
    let store = SessionStore()

    private override init() {
        super.init()
        setupSocketServer()
        setupIsland()
        observeStore()
    }

    func start() {
        discovery.store = store
        discovery.start()
    }

    func stopSocket() {
        socketServer.stop()
    }

    // MARK: - Setup

    private func setupSocketServer() {
        socketServer = SocketServer()
        socketServer.delegate = self
        socketServer.start()
    }

    private func setupIsland() {
        NotchIslandPanel.shared.attach(store: store)
    }

    private func observeStore() {
        store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                NotchIslandPanel.shared.refresh()
            }
        }.store(in: &cancellables)

        // When discovery reports a task just completed → trigger pill flash + sound
        store.taskCompleted.sink { sessionId in
            NotchIslandPanel.shared.flashAlert(for: sessionId)
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}

// MARK: - SocketServerDelegate

extension MenuBarController: SocketServerDelegate {
    func didReceive(event: AgentEventPayload) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let sessionIdStr = event.sessionId,
               let sessionId = UUID(uuidString: sessionIdStr) {
                let agentEvent = AgentEvent(
                    type: self.mapEventType(event.eventType),
                    message: event.message
                )
                self.store.addEvent(to: sessionId, event: agentEvent)

                if event.eventType == "approval_requested" {
                    self.store.requestApproval(
                        sessionId: sessionId,
                        message: event.message,
                        details: nil
                    )
                    self.showNotification(title: "Approval Required", body: event.message)
                }

                if event.eventType == "completed" {
                    self.store.endSession(id: sessionId, status: .completed)
                }
                if event.eventType == "error" {
                    self.store.endSession(id: sessionId, status: .failed)
                }
            } else {
                let agentType = AgentTypeDetector.detect(from: event.agentType ?? event.command ?? "")
                let session = self.store.startSession(
                    agentType: agentType,
                    command: event.command ?? event.message,
                    workingDirectory: event.workingDirectory ?? ""
                )
                let startEvent = AgentEvent(type: .start, message: "Session started")
                self.store.addEvent(to: session.id, event: startEvent)
            }

            NotchIslandPanel.shared.refresh()
            self.store.saveToDisk()
        }
    }

    private func mapEventType(_ type: String) -> AgentEvent.EventType {
        switch type {
        case "start": return .start
        case "stdout": return .stdout
        case "stderr": return .stderr
        case "approval_requested": return .approvalRequested
        case "approval_resolved": return .approvalResolved
        case "file_modified": return .fileModified
        case "command_executed": return .commandExecuted
        case "completed": return .completion
        case "error": return .error
        default: return .stdout
        }
    }

    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
