//
//  AgentSession.swift
//  Argus
//
//  Session model representing a single AI agent execution context.
//

import Foundation

enum AgentType: String, CaseIterable, Codable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case geminiCLI = "Gemini CLI"
    case cursor = "Cursor"
    case openCode = "OpenCode"
    case kimiCode = "Kimi Code"
    case unknown = "Unknown"
}

enum SessionStatus: String, Codable {
    case idle = "Idle"
    case running = "Running"
    case pendingApproval = "Pending Approval"
    case approved = "Approved"
    case denied = "Denied"
    case completed = "Completed"
    case failed = "Failed"

    var displayColor: String {
        switch self {
        case .idle: return "gray"
        case .running: return "blue"
        case .pendingApproval: return "yellow"
        case .approved: return "green"
        case .denied: return "red"
        case .completed: return "green"
        case .failed: return "red"
        }
    }
}

/// Fine-grained state derived from jsonl tailing (independent from SessionStatus).
/// - working: claude is actively generating (last assistant line has no stop_reason,
///            or the last line is a user message newer than the last assistant stop).
/// - idle: claude finished a turn (last assistant line has stop_reason).
/// - completed: process no longer exists.
enum TaskState: String, Codable {
    case working
    case idle
    case completed
}

struct AgentSession: Identifiable, Codable {
    let id: UUID
    let agentType: AgentType
    let command: String
    let workingDirectory: String
    let startTime: Date
    var endTime: Date?
    var status: SessionStatus
    var events: [AgentEvent]
    var pendingRequest: ApprovalRequest?

    // Probe metadata (populated by ClaudeSessionDiscovery)
    var pid: Int32?
    var tty: String?
    var parentBundleId: String?
    var jsonlPath: String?
    var taskState: TaskState
    var lastStopAt: Date?

    init(id: UUID = UUID(),
         agentType: AgentType,
         command: String,
         workingDirectory: String,
         startTime: Date = Date(),
         status: SessionStatus = .idle) {
        self.id = id
        self.agentType = agentType
        self.command = command
        self.workingDirectory = workingDirectory
        self.startTime = startTime
        self.status = status
        self.events = []
        self.pendingRequest = nil
        self.pid = nil
        self.tty = nil
        self.parentBundleId = nil
        self.jsonlPath = nil
        self.taskState = .idle
        self.lastStopAt = nil
    }
}

struct ApprovalRequest: Identifiable, Codable {
    let id: UUID
    let message: String
    let details: String?
    let timestamp: Date
    var resolved: Bool
    var approved: Bool?
    
    init(id: UUID = UUID(), message: String, details: String? = nil) {
        self.id = id
        self.message = message
        self.details = details
        self.timestamp = Date()
        self.resolved = false
        self.approved = nil
    }
}

struct AgentEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: EventType
    let message: String
    
    enum EventType: String, Codable {
        case start
        case stdout
        case stderr
        case approvalRequested
        case approvalResolved
        case fileModified
        case commandExecuted
        case completion
        case error
    }
    
    init(type: EventType, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.message = message
    }
}
