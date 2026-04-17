//
//  SessionStore.swift
//  Argus
//
//  Central observable store for all agent sessions.
//

import Foundation
import Combine

@MainActor
class SessionStore: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var activeSessionCount: Int = 0
    @Published var pendingApprovalCount: Int = 0

    /// Emits when a session's assistant-side turn completes (stop_reason advanced).
    /// UI subscribes to play sound + flash animation.
    let taskCompleted = PassthroughSubject<UUID, Never>()

    private var cancellables = Set<AnyCancellable>()
    
    var activeSessions: [AgentSession] {
        sessions.filter { $0.status == .running || $0.status == .pendingApproval }
    }
    
    var pendingSessions: [AgentSession] {
        sessions.filter { $0.status == .pendingApproval }
    }
    
    // MARK: - Session Lifecycle
    
    func startSession(agentType: AgentType, command: String, workingDirectory: String) -> AgentSession {
        let session = AgentSession(
            agentType: agentType,
            command: command,
            workingDirectory: workingDirectory,
            status: .running
        )
        sessions.append(session)
        updateCounts()
        return session
    }
    
    func endSession(id: UUID, status: SessionStatus = .completed) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].status = status
        sessions[index].endTime = Date()
        updateCounts()
        objectWillChange.send()
    }
    
    func updateSessionStatus(id: UUID, status: SessionStatus) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].status = status
        updateCounts()
        objectWillChange.send()
    }
    
    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        updateCounts()
    }
    
    func clearCompleted() {
        sessions.removeAll { $0.status == .completed || $0.status == .failed }
        updateCounts()
    }
    
    // MARK: - Events
    
    func addEvent(to sessionId: UUID, event: AgentEvent) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].events.append(event)
        objectWillChange.send()
    }
    
    // MARK: - Approvals

    func requestApproval(sessionId: UUID, message: String, details: String? = nil) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let request = ApprovalRequest(message: message, details: details)
        sessions[index].pendingRequest = request
        sessions[index].status = .pendingApproval
        updateCounts()
        objectWillChange.send()
    }
    
    func resolveApproval(sessionId: UUID, approved: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].pendingRequest?.resolved = true
        sessions[index].pendingRequest?.approved = approved
        sessions[index].status = approved ? .approved : .denied

        // Auto-transition back to running if approved
        if approved {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateSessionStatus(id: sessionId, status: .running)
            }
        }
        updateCounts()
        objectWillChange.send()
    }
    
    // MARK: - Probe metadata (from Discovery service)

    func updateProbeMetadata(id: UUID, from probe: SessionProbe) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].pid = probe.pid
        sessions[index].tty = probe.tty
        sessions[index].parentBundleId = probe.parentBundleId
        sessions[index].jsonlPath = probe.jsonlPath
        sessions[index].taskState = probe.taskState
        sessions[index].lastStopAt = probe.lastStopAt
        updateCounts()
        objectWillChange.send()
    }

    func markTaskCompleted(id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].taskState = .completed
        updateCounts()
        objectWillChange.send()
    }

    /// Fires the taskCompleted signal. UI observers play sound + flash.
    func notifyTaskCompleted(sessionId: UUID) {
        taskCompleted.send(sessionId)
    }

    // MARK: - Persistence
    
    func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(sessions)
            let url = Self.sessionsFileURL
            try data.write(to: url)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }
    
    func loadFromDisk() {
        let url = Self.sessionsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            sessions = try JSONDecoder().decode([AgentSession].self, from: data)
            updateCounts()
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
    
    // MARK: - Private
    
    func updateCounts() {
        activeSessionCount = sessions.filter { $0.status == .running }.count
        pendingApprovalCount = sessions.filter { $0.status == .pendingApproval }.count
    }
    
    private static var sessionsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Argus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }
}
