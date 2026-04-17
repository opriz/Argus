//
//  TerminalJumper.swift
//  Argus
//
//  Activates and focuses the terminal window/tab where a given claude CLI
//  process is running. Tier 1: activate the parent terminal app via bundle id.
//  Tier 2: for iTerm2, run AppleScript to select the exact tab by tty.
//

import AppKit
import Foundation

enum TerminalJumper {
    static func jump(to session: AgentSession) {
        let tty = session.tty
        let bundleId = session.parentBundleId
        NSLog("[Jump] session tty=%@ bundle=%@",
              (tty ?? "-") as NSString,
              (bundleId ?? "-") as NSString)

        // Tier 2: iTerm2 deep jump
        if bundleId == "com.googlecode.iterm2", let tty = tty {
            if jumpIterm2(tty: tty) {
                return
            }
            NSLog("[Jump] iTerm2 AppleScript failed, falling back to activation")
        }

        // Tier 1 fallback: just activate the parent app
        guard let bundleId = bundleId else {
            NSLog("[Jump] no bundle id, nothing to do")
            return
        }
        activate(bundleId: bundleId)
    }

    private static func activate(bundleId: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let app = apps.first else {
            NSLog("[Jump] no running instance of %@", bundleId)
            return
        }
        app.activate(options: [])
        NSLog("[Jump] activated %@", bundleId)
    }

    /// Try to focus the iTerm2 tab/session whose tty matches.
    /// Uses the session's `id` (unique per iTerm2 session) to select both the
    /// enclosing tab and the session itself, which reliably raises the tab.
    /// Returns a diagnostic string via AppleScript so we can see what matched.
    private static func jumpIterm2(tty: String) -> Bool {
        // Also try basename form (e.g. "ttys003") in case iTerm2 returns either.
        let ttyBase = (tty as NSString).lastPathComponent
        let script = """
        on run
            set targetFull to "\(tty)"
            set targetBase to "\(ttyBase)"
            tell application "iTerm"
                activate
                set seenTtys to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            set sTty to ""
                            try
                                set sTty to tty of s
                            end try
                            set end of seenTtys to sTty
                            if sTty is targetFull or sTty is targetBase or sTty ends with targetBase then
                                try
                                    select w
                                end try
                                try
                                    tell t to select
                                end try
                                try
                                    tell s to select
                                end try
                                return "ok:" & sTty
                            end if
                        end repeat
                    end repeat
                end repeat
                return "nomatch:" & targetFull & "|seen=" & (seenTtys as string)
            end tell
        end run
        """
        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            NSLog("[Jump] iTerm2 script compile failed")
            return false
        }
        let result = appleScript.executeAndReturnError(&errorDict)
        if let err = errorDict {
            NSLog("[Jump] iTerm2 script error: %@", err)
            return false
        }
        let out = result.stringValue ?? ""
        NSLog("[Jump] iTerm2 result: %@", out as NSString)
        return out.hasPrefix("ok:")
    }
}
