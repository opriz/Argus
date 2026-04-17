//
//  ClaudeSessionDiscovery.swift
//  Argus
//

import Foundation
import Darwin

/// Complete metadata about a live Claude CLI session.
struct SessionProbe {
    let claudeId: String        // Claude's own sessionId (UUID string)
    let cwd: String             // Absolute working directory
    let pid: Int32              // Claude CLI process pid
    let tty: String?            // e.g. "/dev/ttys003"
    let parentBundleId: String? // Parent terminal app bundle id
    let jsonlPath: String       // Absolute path to the jsonl session file
    let taskState: TaskState
    let lastStopAt: Date?       // Timestamp of latest assistant stop_reason
}

// Not @MainActor — thread safety enforced by calling convention:
// apply() and start()/stop() are always called on main thread;
// findActiveSessions() and helpers run on a background queue.
final class ClaudeSessionDiscovery {
    weak var store: SessionStore?

    private var timerSource: DispatchSourceTimer?
    private var knownSessions: [String: UUID] = [:] // claudeId -> our UUID
    private var lastTaskStateByClaudeId: [String: TaskState] = [:]
    private var lastAlertAtByClaudeId: [String: Date] = [:]
    private let alertCooldown: TimeInterval = 3.0
    private var firstScanDone = false

    func start() {
        stop()
        NSLog("[Discovery] start()")

        let src = DispatchSource.makeTimerSource(queue: .main)
        src.schedule(deadline: .now() + 1, repeating: 3)
        src.setEventHandler { [weak self] in
            DispatchQueue.global(qos: .utility).async {
                let found = ClaudeSessionDiscovery.findActiveSessions()
                DispatchQueue.main.async { [weak self] in
                    self?.apply(found)
                }
            }
        }
        src.resume()
        timerSource = src
    }

    func stop() {
        timerSource?.cancel()
        timerSource = nil
    }

    // MARK: - Apply results on main thread

    private func apply(_ found: [SessionProbe]) {
        guard let store = store else { return }

        let seenIds = Set(found.map { $0.claudeId })
        let toAdd = found.filter { knownSessions[$0.claudeId] == nil }
        let existing = found.filter { knownSessions[$0.claudeId] != nil }
        let toRemove = knownSessions.filter { !seenIds.contains($0.key) }

        // New sessions
        for probe in toAdd {
            let session = store.startSession(
                agentType: .claudeCode,
                command: "claude",
                workingDirectory: shortPath(probe.cwd)
            )
            store.updateProbeMetadata(id: session.id, from: probe)
            knownSessions[probe.claudeId] = session.id
            lastTaskStateByClaudeId[probe.claudeId] = probe.taskState
            NSLog("[Discovery] + %@ pid=%d tty=%@ bundle=%@ state=%@",
                  probe.cwd, probe.pid,
                  (probe.tty ?? "-") as NSString,
                  (probe.parentBundleId ?? "-") as NSString,
                  probe.taskState.rawValue as NSString)
        }

        // Existing sessions: update metadata, detect working→idle transition
        let now = Date()
        for probe in existing {
            guard let ourId = knownSessions[probe.claudeId] else { continue }
            let prevState = lastTaskStateByClaudeId[probe.claudeId]
            store.updateProbeMetadata(id: ourId, from: probe)

            if firstScanDone,
               prevState == .working,
               probe.taskState == .idle {
                let lastAlert = lastAlertAtByClaudeId[probe.claudeId]
                if lastAlert == nil || now.timeIntervalSince(lastAlert!) >= alertCooldown {
                    NSLog("[Alert] working→idle (%@)", probe.claudeId.prefix(8) as CVarArg)
                    store.notifyTaskCompleted(sessionId: ourId)
                    lastAlertAtByClaudeId[probe.claudeId] = now
                } else {
                    NSLog("[Alert] suppressed (cooldown) %@", probe.claudeId.prefix(8) as CVarArg)
                }
            }
            lastTaskStateByClaudeId[probe.claudeId] = probe.taskState
        }

        // Sessions whose process vanished
        for (claudeId, ourId) in toRemove {
            if let idx = store.sessions.firstIndex(where: { $0.id == ourId }) {
                if store.sessions[idx].status == .running {
                    store.endSession(id: ourId, status: .completed)
                }
                store.markTaskCompleted(id: ourId)
            }
            knownSessions.removeValue(forKey: claudeId)
            lastTaskStateByClaudeId.removeValue(forKey: claudeId)
            lastAlertAtByClaudeId.removeValue(forKey: claudeId)
            NSLog("[Discovery] - session removed (%@)", claudeId.prefix(8) as CVarArg)
        }

        firstScanDone = true
    }

    // MARK: - Background work (called off main thread)

    private static func findActiveSessions() -> [SessionProbe] {
        let pids = claudePids()
        NSLog("[Discovery] findActiveSessions: %d claude pids found", pids.count)
        var results: [SessionProbe] = []
        var usedJsonls = Set<String>()

        for pid in pids {
            if let probe = probeFor(pid: pid, usedJsonls: &usedJsonls) {
                results.append(probe)
            }
        }
        return results
    }

    /// Builds a SessionProbe for a single pid, or nil if no jsonl can be found.
    private static func probeFor(pid: Int32, usedJsonls: inout Set<String>) -> SessionProbe? {
        // 1. Try lsof first (exact mapping via open fd)
        if let url = jsonlFor(pid: pid), !usedJsonls.contains(url.path) {
            return makeProbe(pid: pid, jsonl: url, source: "lsof", usedJsonls: &usedJsonls)
        }

        // 2. Fallback: find jsonl by modification time (active writes) + creation time (process birth)
        guard let cwd = cwdFor(pid: pid) else {
            NSLog("[Discovery] pid %d: no cwd", pid)
            return nil
        }

        let candidates = jsonlsWithDates(forCwd: cwd)
            .filter { !usedJsonls.contains($0.url.path) }
        guard !candidates.isEmpty else {
            NSLog("[Discovery] pid %d: no jsonl in %@", pid, cwd)
            return nil
        }

        let startTime = procStartTime(pid: pid)
        NSLog("[Discovery] pid %d startTime=%@ candidates=%d",
              pid, (startTime.map { iso8601.string(from: $0) } ?? "nil") as NSString,
              candidates.count)

        var chosen: (url: URL, source: String)? = nil

        // 2a. Active-first: jsonl modified within last 30s (process is writing right now)
        let activeWindow: TimeInterval = 30
        let active = candidates.filter { Date().timeIntervalSince($0.mtime) < activeWindow }
        if !active.isEmpty {
            if let st = startTime {
                let best = active.min {
                    abs($0.ctime.timeIntervalSince(st)) < abs($1.ctime.timeIntervalSince(st))
                }!
                chosen = (best.url, "active-match")
            } else {
                chosen = (active[0].url, "active-recent")
            }
        }

        // 2b. No active jsonl: match by creation time vs process start time
        if chosen == nil, let st = startTime {
            let best = candidates.min {
                abs($0.ctime.timeIntervalSince(st)) < abs($1.ctime.timeIntervalSince(st))
            }!
            let diff = abs(best.ctime.timeIntervalSince(st))
            if diff < 600 {
                chosen = (best.url, "ctime-match")
            }
        }

        // 2c. Last resort: most recently modified jsonl
        if chosen == nil, let first = candidates.first {
            chosen = (first.url, "mtime-fallback")
        }

        guard let (url, source) = chosen else { return nil }
        return makeProbe(pid: pid, jsonl: url, source: source, usedJsonls: &usedJsonls)
    }

    private static func makeProbe(pid: Int32, jsonl: URL, source: String, usedJsonls: inout Set<String>) -> SessionProbe? {
        guard let claudeId = parseSessionId(from: jsonl) else {
            NSLog("[Discovery] pid %d: no sessionId in %@", pid, jsonl.path)
            return nil
        }
        let cwd = cwdFor(pid: pid) ?? jsonl.deletingLastPathComponent().path
        let term = walkToTerminal(from: pid)
        let taskInfo = taskStateFromJsonl(jsonl)
        usedJsonls.insert(jsonl.path)
        NSLog("[Discovery] pid %d -> claudeId=%@ source=%@ jsonl=%@ mtime=%.1fs ago",
              pid, claudeId.prefix(8) as CVarArg, source as NSString, jsonl.lastPathComponent as NSString,
              Date().timeIntervalSince(modificationDate(of: jsonl) ?? .distantPast))
        return SessionProbe(
            claudeId: claudeId,
            cwd: cwd,
            pid: pid,
            tty: term.tty,
            parentBundleId: term.bundleId,
            jsonlPath: jsonl.path,
            taskState: taskInfo.state,
            lastStopAt: taskInfo.lastStopAt
        )
    }

    // MARK: Process tree walking

    /// Walks the ppid chain starting from `pid`, stops at the first ancestor
    /// whose executable resides inside a .app bundle. Returns the child's tty
    /// (which matches across the chain) and the app's bundle identifier.
    private static func walkToTerminal(from pid: Int32) -> (tty: String?, bundleId: String?) {
        let selfTty = ttyFor(pid: pid)
        var current = pid
        for _ in 0..<20 {  // safety: cap walk depth
            guard let info = sysctlInfo(pid: current) else { break }
            let exePath = proc_path(pid: current) ?? ""
            // Check if this process lives in a .app bundle
            if let bundleId = bundleIdFromExePath(exePath) {
                return (selfTty, bundleId)
            }
            let parent = info.kp_eproc.e_ppid
            if parent <= 1 { break }
            current = parent
        }
        return (selfTty, nil)
    }

    private static func ttyFor(pid: Int32) -> String? {
        guard let info = sysctlInfo(pid: pid) else { return nil }
        let tdev = info.kp_eproc.e_tdev
        guard tdev != -1 else { return nil }
        // devname returns e.g. "ttys003"; prepend "/dev/"
        guard let ptr = devname(tdev, mode_t(S_IFCHR)) else { return nil }
        let name = String(cString: ptr)
        return name.isEmpty ? nil : "/dev/\(name)"
    }

    private static func sysctlInfo(pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let res = sysctl(&mib, 4, &info, &size, nil, 0)
        guard res == 0, size > 0 else { return nil }
        return info
    }

    private static func proc_path(pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN = 4096
        var buf = [CChar](repeating: 0, count: 4096)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return nil }
        return String(cString: buf)
    }

    /// Given an executable path like "/Applications/iTerm.app/Contents/MacOS/iTerm2",
    /// extracts the .app bundle identifier.
    private static func bundleIdFromExePath(_ exePath: String) -> String? {
        guard let range = exePath.range(of: ".app/") else { return nil }
        let appPath = String(exePath[..<range.upperBound].dropLast()) // remove trailing "/"
        let url = URL(fileURLWithPath: appPath)
        return Bundle(url: url)?.bundleIdentifier
    }

    // MARK: Process listing (via ps)

    private static func claudePids() -> [Int32] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch {
            NSLog("[Discovery] ps run failed: %@", error.localizedDescription)
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        var pids: [Int32] = []
        for raw in text.split(separator: "\n") {
            let line = raw.drop(while: { $0 == " " })
            guard let spaceIdx = line.firstIndex(of: " ") else { continue }
            let pidStr = String(line[..<spaceIdx])
            let cmd = String(line[line.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            guard let pid = Int32(pidStr) else { continue }
            let argv0 = cmd.split(separator: " ").first.map(String.init) ?? ""
            let base = (argv0 as NSString).lastPathComponent
            if base == "claude" { pids.append(pid) }
        }
        return pids
    }

    private static func cwdFor(pid: Int32) -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-a", "-d", "cwd", "-p", "\(pid)", "-F", "n"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").first(where: { $0.first == "n" }).map { String($0.dropFirst()) }
    }

    /// Returns the process start time via sysctl KERN_PROC_PID.
    /// More reliable than parsing `ps` output.
    private static func procStartTime(pid: Int32) -> Date? {
        guard let info = sysctlInfo(pid: pid) else { return nil }
        let tv_sec = info.kp_proc.p_starttime.tv_sec
        let tv_usec = info.kp_proc.p_starttime.tv_usec
        let interval = TimeInterval(tv_sec) + TimeInterval(tv_usec) / 1_000_000
        return Date(timeIntervalSince1970: interval)
    }

    /// Returns all jsonl files in the given cwd with mtime (for activity) and ctime (for birth matching).
    private static func jsonlsWithDates(forCwd cwd: String) -> [(url: URL, mtime: Date, ctime: Date)] {
        let encoded = cwd.replacingOccurrences(of: "/", with: "-")
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encoded)")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.pathExtension == "jsonl" }.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let ctime = values?.creationDate ?? .distantPast
            let mtime = values?.contentModificationDate ?? .distantPast
            return (url, mtime, ctime)
        }.sorted { $0.mtime > $1.mtime } // most recently modified first
    }

    private static func modificationDate(of url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    /// Ask lsof which .jsonl file this pid has open. This gives a precise
    /// pid->jsonl mapping so multiple claude sessions in the same cwd
    /// are not conflated.
    private static func jsonlFor(pid: Int32) -> URL? {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-a", "-p", "\(pid)", "-F", "n"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else {
            NSLog("[Discovery] jsonlFor pid %d: lsof run failed", pid)
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        var candidates: [URL] = []
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("n") else { continue }
            let path = String(line.dropFirst())
            // Strip lsof's " (deleted)" suffix
            let cleanPath = path.replacingOccurrences(of: " (deleted)", with: "")
            guard cleanPath.hasSuffix(".jsonl") else { continue }
            candidates.append(URL(fileURLWithPath: cleanPath))
        }
        // Prefer files inside .claude/projects and whose basename is a UUID.
        let scored = candidates.map { url -> (url: URL, score: Int) in
            var score = 0
            if url.path.contains(".claude/projects") { score += 2 }
            let name = url.deletingPathExtension().lastPathComponent
            if UUID(uuidString: name) != nil { score += 1 }
            return (url, score)
        }.sorted { $0.score > $1.score }
        if let best = scored.first {
            NSLog("[Discovery] jsonlFor pid %d: found %@ (candidates=%d)", pid, best.url.path as NSString, candidates.count)
            return best.url
        }
        NSLog("[Discovery] jsonlFor pid %d: no .jsonl among %d lines", pid, text.split(separator: "\n").count)
        return nil
    }

    // MARK: JSONL helpers

    private static func findLatestJsonl(forCwd cwd: String) -> URL? {
        let encoded = cwd.replacingOccurrences(of: "/", with: "-")
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encoded)")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return files.filter { $0.pathExtension == "jsonl" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.first
    }

    private static func parseSessionId(from file: URL) -> String? {
        // Claude names jsonl files as <sessionId>.jsonl, so the filename itself
        // is the most reliable source (works even when the file is empty or
        // the first lines haven't been flushed yet).
        let name = file.deletingPathExtension().lastPathComponent
        if UUID(uuidString: name) != nil {
            return name
        }
        // Fallback: read first 16KB looking for sessionId field.
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let text = String(data: (try? handle.read(upToCount: 16384)) ?? Data(), encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sid = json["sessionId"] as? String else { continue }
            return sid
        }
        return nil
    }

    /// Tail the jsonl and derive the current task state.
    /// Reads the last ~32KB, scans lines in reverse order.
    ///
    /// Claude Code writes the complete assistant entry (including stop_reason)
    /// to jsonl *before* streaming output to the terminal, so the jsonl alone
    /// cannot distinguish "streaming" from "done". We use the file's
    /// modification time as a heuristic: if the file was modified within the
    /// last few seconds we treat it as still working.
    private static func taskStateFromJsonl(_ file: URL) -> (state: TaskState, lastStopAt: Date?) {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return (.idle, nil)
        }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize: UInt64 = 32768
        let startOffset = fileSize > readSize ? fileSize - readSize : 0
        try? handle.seek(toOffset: startOffset)
        let data = (try? handle.readToEnd()) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return (.idle, nil) }

        // Parse lines into structured tuples. Skip known non-conversation types.
        struct Entry {
            let type: String
            let timestamp: Date?
            let stopReason: Any?
        }
        var entries: [Entry] = []
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            // Only care about conversation entries
            guard type == "user" || type == "assistant" else { continue }

            let tsString = json["timestamp"] as? String
            let ts = tsString.flatMap { iso8601.date(from: $0) }

            var stop: Any? = nil
            if type == "assistant" {
                // Try nested in message first, then top-level.
                if let msg = json["message"] as? [String: Any] {
                    stop = msg["stop_reason"]
                }
                if stop == nil {
                    stop = json["stop_reason"]
                }
                // stop_reason may be NSNull or empty string
                if stop is NSNull { stop = nil }
                if let str = stop as? String, str.isEmpty { stop = nil }
            }
            entries.append(Entry(type: type, timestamp: ts, stopReason: stop))
        }

        guard let last = entries.last else {
            return (.idle, nil)
        }

        // Find the most recent assistant-with-stop-reason timestamp
        let lastStop = entries.reversed().first(where: { $0.type == "assistant" && $0.stopReason != nil })?.timestamp

        let hasUserMessage = entries.contains { $0.type == "user" }
        let isFinished = last.stopReason != nil && (last.stopReason as? String) != "tool_use"

        // Heuristic: if the jsonl was modified very recently, Claude is likely
        // still streaming output even though the jsonl already contains the
        // full assistant entry with stop_reason.
        // Use stat() directly to bypass macOS file metadata caching.
        var recentModTime: TimeInterval = 0
        let recentlyModified: Bool = file.withUnsafeFileSystemRepresentation { cPath in
            guard let cPath = cPath else { return false }
            var st = stat()
            guard stat(cPath, &st) == 0 else { return false }
            let mod = TimeInterval(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
            recentModTime = mod
            return Date().timeIntervalSince1970 - mod < 3.0
        }

        let state: TaskState
        switch last.type {
        case "user":
            state = .working
        case "assistant":
            if isFinished {
                // Even with stop_reason, if the file is still being written
                // treat as working until the writes settle.
                state = recentlyModified ? .working : .idle
            } else if hasUserMessage {
                state = .working
            } else {
                state = .idle
            }
        default:
            state = .idle
        }
        let stopStr = (last.stopReason as? String) ?? "nil"
        NSLog("[Discovery] state %@ last=%@ stop=%@ isFinished=%d recentlyModified=%d mod=%.1fs ago entries=%d",
              file.lastPathComponent as NSString,
              last.type as NSString,
              stopStr as NSString,
              isFinished,
              recentlyModified,
              Date().timeIntervalSince1970 - recentModTime,
              entries.count)
        return (state, lastStop)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
