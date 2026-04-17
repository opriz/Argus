//
//  SessionRowView.swift
//  Argus
//

import SwiftUI

struct SessionRowView: View {
    let session: AgentSession
    var highlighted: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: AgentTypeDetector.icon(for: session.agentType))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(agentTint.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(agentTint.opacity(0.35), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.agentType.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                    Spacer()
                    StatusBadge(status: session.status)
                }

                Text(session.command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.35))
                    Text(session.workingDirectory)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    Text(formattedDuration)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlighted ? Color.yellow.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(highlighted ? Color.yellow.opacity(0.25) : Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    private var agentTint: Color {
        switch session.agentType {
        case .claudeCode: return .orange
        case .codex: return .blue
        case .geminiCLI: return .purple
        case .cursor: return .cyan
        case .openCode: return .green
        case .kimiCode: return .indigo
        case .unknown: return .gray
        }
    }

    private var formattedDuration: String {
        let end = session.endTime ?? Date()
        let diff = Int(end.timeIntervalSince(session.startTime))
        let m = diff / 60
        let s = diff % 60
        if m > 0 { return String(format: "%d:%02d", m, s) }
        return String(format: "%ds", s)
    }
}
