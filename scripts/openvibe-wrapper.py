#!/usr/bin/env python3
"""
Argus Agent Wrapper
Intercepts AI agent TTY output and forwards events to the macOS menu bar app.

Usage:
    python3 openvibe-wrapper.py claude <args...>
    python3 openvibe-wrapper.py codex <args...>

Install:
    cp openvibe-wrapper.py /usr/local/bin/openvibe-wrapper
    alias claude='openvibe-wrapper claude'
"""

import json
import os
import re
import select
import socket
import subprocess
import sys
import termios
import tty

SOCKET_PATH = "/tmp/argus.sock"

APPROVAL_PATTERNS = [
    re.compile(r"Allow .+ to edit files\?.*\(Y/n\)", re.IGNORECASE),
    re.compile(r"Do you want to proceed\?.*\[Y/n\]", re.IGNORECASE),
    re.compile(r"Proceed with changes\?.*\(y/N\)", re.IGNORECASE),
    re.compile(r"Approve .+\?", re.IGNORECASE),
    re.compile(r"\(y/N\)", re.IGNORECASE),
    re.compile(r"\(Y/n\)", re.IGNORECASE),
]

SESSION_ID = None
AGENT_TYPE = sys.argv[1] if len(sys.argv) > 1 else "unknown"
COMMAND = " ".join(sys.argv[1:])
CWD = os.getcwd()


def send_event(event_type: str, message: str, session_id: str = None):
    """Send JSON event to the macOS app via Unix socket."""
    payload = {
        "sessionId": session_id,
        "agentType": AGENT_TYPE,
        "eventType": event_type,
        "command": COMMAND,
        "workingDirectory": CWD,
        "message": message,
        "timestamp": None,
    }
    data = json.dumps(payload).encode("utf-8")
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.1)
            s.connect(SOCKET_PATH)
            s.sendall(data)
    except (FileNotFoundError, ConnectionRefusedError, OSError, socket.timeout):
        # App not running, silently drop
        pass


def detect_approval(line: str) -> str:
    """Check if a line contains an approval request."""
    for pattern in APPROVAL_PATTERNS:
        match = pattern.search(line)
        if match:
            return line.strip()
    return None


def main():
    global SESSION_ID

    # Spawn the real agent command in a PTY so we can intercept all I/O
    master_fd, slave_fd = os.openpty()

    pid = os.fork()
    if pid == 0:
        # Child: run the real agent
        os.close(master_fd)
        os.setsid()
        os.dup2(slave_fd, 0)
        os.dup2(slave_fd, 1)
        os.dup2(slave_fd, 2)
        os.execvp(sys.argv[1], sys.argv[1:])
        sys.exit(1)

    os.close(slave_fd)

    # Save terminal settings
    old_tty = termios.tcgetattr(sys.stdin.fileno()) if sys.stdin.isatty() else None
    if old_tty:
        tty.setcbreak(sys.stdin.fileno())

    # Register new session
    send_event("start", f"Started: {COMMAND}")
    # After start, we don't have the session ID from the app yet.
    # In a production version, the app should reply with the session ID.
    # For now, we rely on the app matching by command/agentType.

    try:
        buffer = b""
        approval_sent = False

        while True:
            readable, _, _ = select.select([master_fd, sys.stdin.fileno()], [], [], 0.05)

            if master_fd in readable:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    break
                if not data:
                    break

                # Forward to real stdout
                sys.stdout.buffer.write(data)
                sys.stdout.flush()

                buffer += data
                while b"\n" in buffer:
                    idx = buffer.index(b"\n")
                    line = buffer[: idx + 1].decode("utf-8", errors="replace")
                    buffer = buffer[idx + 1 :]

                    # Detect approval requests
                    approval = detect_approval(line)
                    if approval and not approval_sent:
                        send_event("approval_requested", approval)
                        approval_sent = True

                    # Detect completion/failure patterns (optional)
                    if "error" in line.lower() or "failed" in line.lower():
                        send_event("stderr", line.strip())
                    else:
                        send_event("stdout", line.strip())

            if sys.stdin.fileno() in readable:
                try:
                    user_input = os.read(sys.stdin.fileno(), 4096)
                except OSError:
                    break
                if not user_input:
                    break
                os.write(master_fd, user_input)

                # If user typed 'y' after approval request, reset flag
                if approval_sent and user_input.strip() in (b"y", b"Y", b"yes"):
                    approval_sent = False

    except KeyboardInterrupt:
        pass
    finally:
        if old_tty:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_tty)
        os.close(master_fd)
        _, status = os.waitpid(pid, 0)
        exit_code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1

        if exit_code == 0:
            send_event("completed", "Session completed successfully")
        else:
            send_event("error", f"Session exited with code {exit_code}")

        sys.exit(exit_code)


if __name__ == "__main__":
    main()
