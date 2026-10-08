import Darwin
import Foundation
import StatusCore

// Claude Code runs this with the hook payload on stdin. It prints nothing and always exits 0.
// It doubles as a CLI: `csl-hook install | uninstall | status`.

let args = CommandLine.arguments.dropFirst()

func printUsage() {
    print("""
    csl-hook: Claude Status Light hook helper

      csl-hook install     Add Claude Status Light hooks to ~/.claude/settings.json
      csl-hook uninstall   Remove them (other hooks are left untouched)
      csl-hook status      Show whether hooks are installed

    With no arguments it reads a Claude Code hook payload from stdin.
    """)
}

switch args.first {
case nil:
    if isatty(STDIN_FILENO) != 0 {
        printUsage()
    } else {
        let payload = FileHandle.standardInput.readDataToEndOfFile()
        HookRunner.handle(payload: payload, environment: ProcessInfo.processInfo.environment)
    }
    exit(0)

case "install":
    do {
        if let me = Bundle.main.executableURL?.resolvingSymlinksInPath(),
           me.path != Paths.hookBinary.resolvingSymlinksInPath().path {
            try HelperInstaller.sync(from: me)
        }
        try HooksInstaller.install()
        print("Installed hooks for \(HookReducer.registeredEvents.count) events in \(Paths.claudeSettings.path)")
    } catch {
        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case "uninstall":
    do {
        try HooksInstaller.uninstall()
        print("Removed Claude Status Light hooks from \(Paths.claudeSettings.path)")
    } catch {
        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case "status":
    switch HooksInstaller.status() {
    case .installed: print("installed")
    case .notInstalled: print("not installed")
    case .outdated: print("outdated (run: csl-hook install)")
    case .unreadable(let why): print("settings.json unreadable: \(why)")
    }

default:
    printUsage()
    exit(2)
}
