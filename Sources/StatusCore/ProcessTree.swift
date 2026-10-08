import Darwin
import Foundation

public struct ProcInfo: Equatable, Sendable {
    public var pid: pid_t
    public var ppid: pid_t
    public var name: String
    public var startTime: Double
}

/// Process lookups via sysctl: microseconds, no subprocesses.
public enum ProcessTree {
    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "tcsh", "csh", "env"]

    public static func info(_ pid: pid_t) -> ProcInfo? {
        guard pid > 0 else { return nil }
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &kinfo, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: kinfo.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let start = kinfo.kp_proc.p_un.__p_starttime
        return ProcInfo(pid: pid, ppid: kinfo.kp_eproc.e_ppid, name: name,
                        startTime: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }

    /// From inside a hook: skip the shell(s) Claude used to run us, the next process up is Claude.
    /// Then keep climbing to the process launchd started, which is the hosting app
    /// (Terminal, iTerm, Ghostty, VS Code, Claude desktop...).
    public static func locateClaude(from start: pid_t = getppid()) -> (claude: ProcInfo?, appPid: pid_t?) {
        var current = info(start)
        var hops = 0
        while let proc = current, shells.contains(proc.name), hops < 8 {
            current = info(proc.ppid)
            hops += 1
        }
        guard let claude = current else { return (nil, nil) }

        var top = claude
        hops = 0
        while top.ppid > 1, let parent = info(top.ppid), hops < 32 {
            top = parent
            hops += 1
        }
        return (claude, top.ppid == 1 ? top.pid : nil)
    }

    /// True if `pid` is running and (when known) is the same process that was recorded.
    public static func isAlive(pid: pid_t, startTime: Double?) -> Bool {
        guard let proc = info(pid) else { return false }
        if let startTime, abs(proc.startTime - startTime) > 0.5 { return false }
        return true
    }
}
