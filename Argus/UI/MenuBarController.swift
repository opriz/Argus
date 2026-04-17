//
//  MenuBarController.swift
//  Argus
//

import SwiftUI
import AppKit
import Combine

final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var socketServer: SocketServer!
    private let discovery = ClaudeSessionDiscovery()
    let store = SessionStore()

    private override init() {
        super.init()
        setupStatusItem()
        setupPopover()
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

    private func setupStatusItem() {
        let statusBar = sharedStatusBar()
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform.path.ecg",
            accessibilityDescription: "Argus"
        )
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
        updateMenuBarTitle()
    }

    private func sharedStatusBar() -> NSStatusBar {
        let cls = NSClassFromString("NSStatusBar") as! NSObject.Type
        let sel = NSSelectorFromString("systemStatusBar")
        guard let result = cls.perform(sel) else {
            fatalError("Unable to get NSStatusBar instance")
        }
        return result.takeUnretainedValue() as! NSStatusBar
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: SessionListView().environmentObject(store)
        )
    }

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
                self?.updateMenuBarTitle()
                NotchIslandPanel.shared.refresh()
            }
        }.store(in: &cancellables)

        // When discovery reports a task just completed → trigger pill flash + sound
        store.taskCompleted.sink { sessionId in
            NotchIslandPanel.shared.flashAlert(for: sessionId)
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    func updateMenuBarTitle() {
        let pending = store.pendingApprovalCount
        let active = store.activeSessionCount
        if pending > 0 {
            statusItem.button?.title = " \(pending)"
            statusItem.button?.contentTintColor = .systemYellow
        } else if active > 0 {
            statusItem.button?.title = " \(active)"
            statusItem.button?.contentTintColor = .systemGreen
        } else {
            statusItem.button?.title = ""
            statusItem.button?.contentTintColor = nil
        }
    }
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

            self.updateMenuBarTitle()
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
