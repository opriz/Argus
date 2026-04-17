//
//  AgentTypeDetector.swift
//  Argus
//
//  Detects agent type from command string or process name.
//

import Foundation

enum AgentTypeDetector {
    static func detect(from command: String) -> AgentType {
        let lower = command.lowercased()
        if lower.contains("claude") { return .claudeCode }
        if lower.contains("codex") { return .codex }
        if lower.contains("gemini") { return .geminiCLI }
        if lower.contains("cursor") { return .cursor }
        if lower.contains("opencode") { return .openCode }
        if lower.contains("kimi") { return .kimiCode }
        return .unknown
    }
    
    static func icon(for type: AgentType) -> String {
        switch type {
        case .claudeCode: return "bubble.left.fill"
        case .codex: return "cube.fill"
        case .geminiCLI: return "star.fill"
        case .cursor: return "cursorarrow"
        case .openCode: return "terminal.fill"
        case .kimiCode: return "moon.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    static func color(for type: AgentType) -> String {
        switch type {
        case .claudeCode: return "orange"
        case .codex: return "blue"
        case .geminiCLI: return "purple"
        case .cursor: return "cyan"
        case .openCode: return "green"
        case .kimiCode: return "indigo"
        case .unknown: return "gray"
        }
    }
}
