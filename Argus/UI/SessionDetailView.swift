//
//  SessionDetailView.swift
//  Argus
//

import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    let session: AgentSession
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                Divider()
                if let request = session.pendingRequest, !request.resolved {
                    approvalCard(request: request)
                }
                eventsSection
            }
            .padding()
        }
        .frame(minWidth: 320, minHeight: 400)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: AgentTypeDetector.icon(for: session.agentType))
                    .font(.title2)
                Text(session.agentType.rawValue)
                    .font(.title3)
                Spacer()
                StatusBadge(status: session.status)
            }
            Text(session.command)
                .font(.system(.body, design: .monospaced))
            Text(session.workingDirectory)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func approvalCard(request: ApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Approval Required")
                    .font(.headline)
                Spacer()
            }
            Text(request.message)
                .font(.body)
            if let details = request.details {
                Text(details)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            HStack(spacing: 12) {
                Button("Deny") {
                    store.resolveApproval(sessionId: session.id, approved: false)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Allow") {
                    store.resolveApproval(sessionId: session.id, approved: true)
                }
                .keyboardShortcut("y", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }
    
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(session.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Text(event.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Text(event.message)
                        .font(.caption)
                    Spacer()
                }
            }
        }
    }
}
