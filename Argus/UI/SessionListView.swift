//
//  SessionListView.swift
//  Argus
//

import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedSession: AgentSession?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.white.opacity(0.06))
            sessionList
        }
        .frame(width: 380, height: 520)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .preferredColorScheme(.dark)
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(Color(red: 0.55, green: 0.9, blue: 0.55))
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text("Argus")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    if store.activeSessionCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(Color(red: 0.55, green: 0.9, blue: 0.55)).frame(width: 5, height: 5)
                            Text("\(store.activeSessionCount) running")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    if store.pendingApprovalCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(Color.yellow).frame(width: 5, height: 5)
                            Text("\(store.pendingApprovalCount) pending")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow.opacity(0.9))
                        }
                    }
                    if store.activeSessionCount == 0 && store.pendingApprovalCount == 0 {
                        Text("No agents running")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            Spacer()
            Button(action: { store.clearCompleted() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Clear completed sessions")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.02))
    }

    private var sessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !store.pendingSessions.isEmpty {
                    section(title: "Needs Approval", tint: .yellow) {
                        ForEach(store.pendingSessions) { session in
                            SessionRowView(session: session, highlighted: true)
                                .onTapGesture { selectedSession = session }
                        }
                    }
                }

                if !store.activeSessions.filter({ $0.status == .running }).isEmpty {
                    section(title: "Active", tint: Color(red: 0.55, green: 0.9, blue: 0.55)) {
                        ForEach(store.activeSessions.filter { $0.status == .running }) { session in
                            SessionRowView(session: session)
                                .onTapGesture { selectedSession = session }
                        }
                    }
                }

                let recent = store.sessions.filter { $0.status == .completed || $0.status == .failed || $0.status == .denied }
                if !recent.isEmpty {
                    section(title: "Recent", tint: .white.opacity(0.4)) {
                        ForEach(recent) { session in
                            SessionRowView(session: session)
                                .onTapGesture { selectedSession = session }
                        }
                    }
                }

                if store.sessions.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .sheet(item: $selectedSession) { session in
            SessionDetailView(session: session)
                .environmentObject(store)
                .frame(minWidth: 360, minHeight: 400)
        }
    }

    private func section<Content: View>(title: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 4)
            content()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.25))
            Text("No sessions yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text("Run an AI agent via the wrapper\nto see it appear here.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

}
