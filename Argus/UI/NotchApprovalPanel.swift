//
//  NotchApprovalPanel.swift
//  Argus
//
//  Persistent Dynamic Island-style panel that lives just below the notch.
//  Shows a pill when sessions are running; expands to a full session list
//  when the user clicks it.
//

import SwiftUI
import AppKit
import Combine

final class NotchIslandPanel: NSPanel {
    enum Mode { case hidden, pill, expanded }

    static let shared = NotchIslandPanel()

    private weak var store: SessionStore?
    private var mode: Mode = .hidden
    private var hostingController: NSHostingController<NotchIslandContent>?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Alerts published to SwiftUI for flash animations.
    private let alertSubject = PassthroughSubject<UUID, Never>()

    /// Top inset so the notch passes through the panel without covering content.
    /// Only used in the expanded card — the pill sits entirely within the
    /// menu bar strip so no inset is needed there.
    static let notchInset: CGFloat = 32
    private let expandedWidth: CGFloat = 540
    /// Pill spans across the notch so the physical obstruction sits in the
    /// middle gap; left/right content remains visible.
    private let pillWidth: CGFloat = 280
    private let pillHeight: CGFloat = 32
    private var pillSize: NSSize { NSSize(width: pillWidth, height: pillHeight) }
    private let minExpandedHeight: CGFloat = 200
    private let maxExpandedHeight: CGFloat = 560

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: pillWidth, height: pillHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false
        self.ignoresMouseEvents = false
        self.animationBehavior = .none
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func attach(store: SessionStore) {
        self.store = store
        let content = NotchIslandContent(
            store: store,
            alertPublisher: alertSubject.eraseToAnyPublisher(),
            onExpand: { [weak self] in self?.setMode(.expanded, animated: true) },
            onCollapse: { [weak self] in self?.setMode(.pill, animated: true) }
        )
        let hc = NSHostingController(rootView: content)
        self.contentViewController = hc
        self.hostingController = hc
    }

    func refresh() {
        guard let store = store else { return }
        let hasPending = store.pendingApprovalCount > 0
        let visible = store.sessions.filter { $0.taskState != .completed && $0.status != .completed }
        let hasAny = !visible.isEmpty
        let target: Mode
        if hasPending {
            target = .expanded
        } else if hasAny {
            target = (mode == .expanded) ? .expanded : .pill
        } else {
            target = .hidden
        }
        setMode(target, animated: true)
    }

    /// Triggers the flash animation + sound for a completed session.
    func flashAlert(for sessionId: UUID) {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        }
        alertSubject.send(sessionId)
    }

    private func setMode(_ newMode: Mode, animated: Bool) {
        if newMode == mode && self.isVisible { return }

        if newMode == .expanded {
            if outsideClickMonitor == nil {
                outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self = self else { return }
                    let loc = event.locationInWindow
                    let screen = NSScreen.main?.frame ?? .zero
                    let flipped = NSPoint(x: loc.x, y: screen.height - loc.y)
                    if !self.frame.contains(flipped) {
                        if self.store?.pendingApprovalCount == 0 {
                            self.setMode(.pill, animated: true)
                        }
                    }
                }
            }
        } else {
            if let monitor = outsideClickMonitor {
                NSEvent.removeMonitor(monitor)
                outsideClickMonitor = nil
            }
        }

        guard let screen = NSScreen.main else { return }
        let size: NSSize
        if newMode == .expanded {
            size = NSSize(width: expandedWidth, height: computeExpandedHeight())
        } else {
            size = pillSize
        }
        let origin = Self.notchOrigin(for: size, on: screen)
        let target = NSRect(origin: origin, size: size)

        hostingController?.rootView.modeBinding = newMode

        switch (mode, newMode) {
        case (_, .hidden):
            animateOut()
        case (.hidden, _):
            self.setFrame(target, display: false)
            var start = target
            start.origin.y += 14
            self.setFrame(start, display: false)
            self.alphaValue = 0
            self.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animated ? 0.22 : 0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(target, display: true)
                self.animator().alphaValue = 1
            }
        default:
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animated ? 0.28 : 0
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)
                self.animator().setFrame(target, display: true)
            }
        }
        mode = newMode
    }

    private func computeExpandedHeight() -> CGFloat {
        guard let store = store else { return minExpandedHeight }
        let visible = store.sessions.filter { $0.taskState != .completed && $0.status != .completed }
        let approvalPad: CGFloat = store.pendingApprovalCount > 0 ? 140 : 0
        let rows = visible.count
        let listHeight: CGFloat = 36 + CGFloat(rows) * 52 + 24
        let total = approvalPad + listHeight + Self.notchInset
        return min(max(total, minExpandedHeight), maxExpandedHeight)
    }

    private func animateOut() {
        guard self.isVisible else { mode = .hidden; return }
        var exit = self.frame
        exit.origin.y += 10
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().setFrame(exit, display: true)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    private static func notchOrigin(for size: NSSize, on screen: NSScreen) -> NSPoint {
        let frame = screen.frame
        let centerX = frame.midX - size.width / 2
        // Anchor the panel's top edge to the very top of the screen so the
        // physical notch sits inside the panel rather than below it.
        let topY = frame.maxY - size.height
        return NSPoint(x: centerX, y: topY)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - SwiftUI Content

struct NotchIslandContent: View {
    @ObservedObject var store: SessionStore
    let alertPublisher: AnyPublisher<UUID, Never>
    var onExpand: () -> Void
    var onCollapse: () -> Void
    var modeBinding: NotchIslandPanel.Mode = .pill

    @State private var flashingIds: Set<UUID> = []
    @State private var pillFlashing: Bool = false
    @State private var hoverCollapseWork: DispatchWorkItem?
    /// Ignore hover events while the panel is animating between pill/expanded
    /// to prevent frame-change jitter from triggering expand/collapse loops.
    @State private var ignoreHoverUntil: Date = .distantPast

    var body: some View {
        Group {
            if modeBinding == .expanded {
                expandedCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                pill
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: modeBinding)
        .onHover { inside in
            guard Date() >= ignoreHoverUntil else { return }
            hoverCollapseWork?.cancel()
            if inside {
                if modeBinding != .expanded {
                    ignoreHoverUntil = Date().addingTimeInterval(0.35)
                    onExpand()
                }
            } else {
                let work = DispatchWorkItem {
                    guard Date() >= ignoreHoverUntil else { return }
                    if store.pendingApprovalCount == 0 {
                        ignoreHoverUntil = Date().addingTimeInterval(0.35)
                        onCollapse()
                    }
                }
                hoverCollapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
            }
        }
        .onReceive(alertPublisher) { sessionId in
            flashingIds.insert(sessionId)
            pillFlashing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                flashingIds.remove(sessionId)
                pillFlashing = false
            }
        }
    }

    // MARK: Pill (collapsed)

    private var pill: some View {
        Capsule()
            .fill(Color.black.opacity(0.92))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Capsule()
                    .strokeBorder(pillFlashing ? Color.green : Color.white.opacity(0.06),
                                  lineWidth: pillFlashing ? 2.5 : 0.5)
            )
            .overlay(
                HStack(spacing: 0) {
                    if hasWorking {
                        PulsingIcon(name: "waveform.path.ecg", color: pillTint)
                            .padding(.leading, 18)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(pillTint)
                            .padding(.leading, 18)
                    }
                    Spacer(minLength: 0)
                    if hasWorking {
                        PulsingDot(color: pillTint)
                            .padding(.trailing, 18)
                    } else {
                        Circle().fill(pillTint).frame(width: 7, height: 7)
                            .padding(.trailing, 18)
                    }
                }
            )
            .contentShape(Capsule())
            .onTapGesture { onExpand() }
    }

    // MARK: Expanded card

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session = approvalSession {
                approvalSection(session: session)
                Divider().background(Color.white.opacity(0.1))
            }
            headerRow
            sessionList
        }
        .padding(14)
        .padding(.top, NotchIslandPanel.notchInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 22, x: 0, y: 10)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Sessions")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.55))
            Text("\(visibleSessions.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            HStack(spacing: 6) {
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(orderedSessions) { session in
                    SessionCompactRow(
                        session: session,
                        flashing: flashingIds.contains(session.id),
                        onTap: { jump(to: session) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func approvalSection(session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("Needs Approval")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                Spacer()
                Text(session.workingDirectory)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            if let req = session.pendingRequest {
                Text(req.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3)
                if let details = req.details {
                    Text(details)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05))
                        )
                }
            }
            HStack(spacing: 10) {
                Spacer()
                Button {
                    store.resolveApproval(sessionId: session.id, approved: false)
                } label: {
                    Text("Deny")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    store.resolveApproval(sessionId: session.id, approved: true)
                } label: {
                    Text("Allow")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.65, green: 1.0, blue: 0.6)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("y", modifiers: .command)
            }
        }
    }

    // MARK: Helpers

    /// Sessions that are still alive (not completed).
    private var visibleSessions: [AgentSession] {
        store.sessions.filter { $0.taskState != .completed && $0.status != .completed }
    }

    private var approvalSession: AgentSession? {
        visibleSessions.first { $0.status == .pendingApproval }
    }

    /// Order sessions: working first, then idle.
    private var orderedSessions: [AgentSession] {
        visibleSessions.sorted { a, b in
            let ra = rank(a)
            let rb = rank(b)
            if ra != rb { return ra < rb }
            return a.startTime > b.startTime
        }
    }

    private func rank(_ session: AgentSession) -> Int {
        switch session.taskState {
        case .working: return 0
        case .idle: return 1
        case .completed: return 2
        }
    }

    private var hasWorking: Bool {
        visibleSessions.contains { $0.taskState == .working }
    }

    private var hasIdle: Bool {
        visibleSessions.contains { $0.taskState == .idle }
    }

    private var pillLabel: String {
        if let pending = approvalSession {
            return "Approve \(pending.agentType.rawValue)"
        }
        let working = visibleSessions.filter { $0.taskState == .working }.count
        let idle = visibleSessions.filter { $0.taskState == .idle }.count
        if working > 0 {
            return "Working · \(working)\(idle > 0 ? " · \(idle) idle" : "")"
        }
        if idle > 0 {
            return "Idle · \(idle)"
        }
        if visibleSessions.isEmpty {
            return "Idle"
        }
        return "Done · \(visibleSessions.count)"
    }

    private var pillTint: Color {
        if approvalSession != nil { return .yellow }
        if hasWorking { return Color(red: 0.55, green: 0.9, blue: 0.55) }
        if hasIdle { return Color(red: 0.5, green: 0.7, blue: 1.0) }
        return .gray
    }

    private func jump(to session: AgentSession) {
        TerminalJumper.jump(to: session)
    }
}

// MARK: - Session row (compact)

struct SessionCompactRow: View {
    let session: AgentSession
    let flashing: Bool
    let onTap: () -> Void
    @State private var hovering: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            stateIndicator
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayPath)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(session.taskState == .completed ? 0.5 : 0.95))
                        .lineLimit(1)
                    Spacer()
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(stateColor.opacity(0.95))
                }
                HStack(spacing: 4) {
                    if let pid = session.pid {
                        Text("pid \(pid)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    if let tty = session.tty?.replacingOccurrences(of: "/dev/", with: "") {
                        Text("· \(tty)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    Text(durationText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            if session.tty != nil || session.parentBundleId != nil {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(flashing ? stateColor : (hovering ? Color.white.opacity(0.18) : Color.white.opacity(0.05)),
                        lineWidth: flashing ? 1.5 : (hovering ? 1 : 0.5))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onTap() }
        .opacity(session.taskState == .completed ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private var rowFillColor: Color {
        if flashing { return stateColor.opacity(0.25) }
        if hovering { return Color.white.opacity(0.1) }
        return Color.white.opacity(0.03)
    }

    private var stateIndicator: some View {
        Group {
            if session.taskState == .working {
                PulsingDot(color: stateColor)
                    .frame(width: 10, height: 10)
            } else {
                Circle().fill(stateColor).frame(width: 8, height: 8)
            }
        }
        .frame(width: 14)
    }

    private var stateColor: Color {
        switch session.taskState {
        case .working: return Color(red: 0.55, green: 0.9, blue: 0.55)
        case .idle: return Color(red: 0.5, green: 0.7, blue: 1.0)
        case .completed: return Color.white.opacity(0.3)
        }
    }

    private var statusLabel: String {
        if session.status == .pendingApproval { return "Needs approval" }
        switch session.taskState {
        case .working: return "Working…"
        case .idle: return "Waiting"
        case .completed: return "Done"
        }
    }

    private var displayPath: String {
        let path = session.workingDirectory
        // Show last 2 path components for brevity if path is long
        let comps = path.split(separator: "/")
        if comps.count > 2 {
            return "…/\(comps.suffix(2).joined(separator: "/"))"
        }
        return path
    }

    private var durationText: String {
        let end = session.endTime ?? Date()
        let diff = Int(end.timeIntervalSince(session.startTime))
        let m = diff / 60
        let s = diff % 60
        if m > 59 {
            let h = m / 60
            return "\(h)h\(m % 60)m"
        }
        if m > 0 { return "\(m)m\(s)s" }
        return "\(s)s"
    }
}

// MARK: - Small components

struct PulsingIcon: View {
    let name: String
    let color: Color

    var body: some View {
        PulsingIconRepresentable(name: name, color: NSColor(color))
            .frame(width: 14, height: 14)
    }
}

struct PulsingIconRepresentable: NSViewRepresentable {
    let name: String
    let color: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        imageView.contentTintColor = color
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(pulse, forKey: "pulse")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.2
        scale.duration = 1.0
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(scale, forKey: "scale")

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let imageView = nsView.subviews.first as? NSImageView {
            imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            imageView.contentTintColor = color
        }
    }
}

struct PulsingDot: View {
    let color: Color

    var body: some View {
        PulsingDotRepresentable(color: NSColor(color))
            .frame(width: 6, height: 6)
    }
}

struct PulsingDotRepresentable: NSViewRepresentable {
    let color: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = CALayer()
        layer.backgroundColor = color.cgColor
        layer.cornerRadius = 3
        layer.frame = CGRect(x: 0, y: 0, width: 6, height: 6)
        view.layer = layer

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.45
        scale.duration = 1.0
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(scale, forKey: "pulse")

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.35
        opacity.duration = 1.0
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(opacity, forKey: "opacity")

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.backgroundColor = color.cgColor
    }
}
