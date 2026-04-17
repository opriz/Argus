//
//  StatusBadge.swift
//  Argus
//

import SwiftUI

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .overlay(status == .running ? AnyView(PulsingDot(color: statusColor)) : AnyView(EmptyView()))
            Text(status.rawValue)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(statusColor.opacity(0.95))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(statusColor.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(statusColor.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .gray
        case .running: return Color(red: 0.55, green: 0.9, blue: 0.55)
        case .pendingApproval: return .yellow
        case .approved: return .green
        case .denied: return .red
        case .completed: return .green.opacity(0.7)
        case .failed: return .red
        }
    }
}
