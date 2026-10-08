import XCTest
@testable import StatusCore

final class InstallerTests: XCTestCase {
    private var sandbox: URL!

    // Keep backups and helper paths out of the developer's real ~/.claude-status-light.
    override func setUp() {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("csl-tests-\(UUID().uuidString)")
        setenv("CLAUDE_STATUS_LIGHT_DIR", sandbox.path, 1)
    }

    override func tearDown() {
        unsetenv("CLAUDE_STATUS_LIGHT_DIR")
        try? FileManager.default.removeItem(at: sandbox)
    }

    /// Shaped like a real settings.json with someone else's hooks already present.
    let original = """
    {
      "model": "opus",
      "hooks": {
        "Stop": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "node \\"/Users/me/.claude/notify-plus.js\\" # other-tool",
                "timeout": 10,
                "async": true
              }
            ]
          }
        ]
      },
      "modelSettings": {
        "claude-opus-5-5": {
          "effortLevel": "high"
        }
      },
      "ratio": 1.50,
      "emoji": "héllo \\ud83d\\ude00 \\"q\\" \\n",
      "enabledPlugins": {}
    }

    """

    func testJSONRoundTripIsByteIdentical() throws {
        let value = try JSONValue.parse(Data(original.utf8))
        let expected = original.replacingOccurrences(of: "\\ud83d\\ude00", with: "😀")
        XCTAssertEqual(value.serialized() + "\n", expected)
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(try JSONValue.parse(Data("{\"a\": 1,}".utf8)))
        XCTAssertThrowsError(try JSONValue.parse(Data("{\"a\": 1} x".utf8)))
        XCTAssertThrowsError(try JSONValue.parse(Data("// comment\n{}".utf8)))
    }

    func testInstallMergesAndUninstallRestores() throws {
        let root = try JSONValue.parse(Data(original.utf8))
        XCTAssertEqual(HooksInstaller.status(of: root), .notInstalled)

        let (installed, chain) = try HooksInstaller.addingOurs(to: root, chain: nil)
        XCTAssertNil(chain, "no status line to wrap")
        XCTAssertEqual(HooksInstaller.status(of: installed), .installed)

        // The other tool's Stop hook is kept, and ours is appended after it.
        let stop = installed["hooks"]?["Stop"]?.array
        XCTAssertEqual(stop?.count, 2)
        XCTAssertEqual(stop?.first, root["hooks"]?["Stop"]?.array?.first)
        // Unrelated keys keep their order; the status line is appended since there wasn't one.
        XCTAssertEqual(installed.members?.map(\.key), (root.members?.map(\.key) ?? []) + ["statusLine"])

        // Installing twice doesn't duplicate.
        XCTAssertEqual(try HooksInstaller.addingOurs(to: installed, chain: chain).root, installed)

        XCTAssertEqual(HooksInstaller.removingOurs(from: installed, chain: chain), root)
    }

    func testUninstallDropsHooksKeyItCreated() throws {
        let root = try JSONValue.parse(Data(#"{"model": "opus"}"#.utf8))
        let installed = try HooksInstaller.addingOurs(to: root, chain: nil).root
        XCTAssertEqual(HooksInstaller.removingOurs(from: installed, chain: nil), root)
    }

    func testOutdatedDetection() throws {
        var root = try HooksInstaller.addingOurs(to: .object([]), chain: nil).root
        var hooks = root["hooks"]!
        hooks["StopFailure"] = nil
        root["hooks"] = hooks
        XCTAssertEqual(HooksInstaller.status(of: root), .outdated)
    }

    func testRefusesUnexpectedShapes() {
        XCTAssertThrowsError(try HooksInstaller.addingOurs(to: .array([]), chain: nil))
        XCTAssertThrowsError(try HooksInstaller.addingOurs(to: .object([JSONMember("hooks", .string("x"))]), chain: nil))
    }

    func testFileInstallKeepsBackupAndSymlink() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real-settings.json")
        let link = dir.appendingPathComponent("settings.json")
        try Data(original.utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try HooksInstaller.install(settings: link)
        XCTAssertEqual(HooksInstaller.status(settings: link), .installed)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), real.path)

        try HooksInstaller.uninstall(settings: link)
        let after = try JSONValue.parse(Data(contentsOf: real))
        XCTAssertEqual(after, try JSONValue.parse(Data(original.utf8)))
    }

    func testWrapsAndRestoresUsersStatusLine() throws {
        let text = """
        {
          "statusLine": {
            "type": "command",
            "command": "~/bin/my-status.sh",
            "padding": 2
          },
          "model": "opus"
        }

        """
        let dir = sandbox!
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json")
        try Data(text.utf8).write(to: file)

        try HooksInstaller.install(settings: file)
        let installed = try JSONValue.parse(Data(contentsOf: file))
        XCTAssertEqual(HooksInstaller.status(of: installed), .installed)
        XCTAssertTrue(installed["statusLine"]?["command"]?.string?.contains("csl-hook\" statusline") ?? false)
        XCTAssertEqual(installed["statusLine"]?["padding"], .number("2"), "keeps the user's display options")
        XCTAssertEqual(installed.members?.first?.key, "statusLine", "replaced in place")
        XCTAssertEqual(StatusLineRunner.chainedCommand(), "~/bin/my-status.sh")

        // Reinstalling must keep wrapping the user's command, not our own.
        try HooksInstaller.install(settings: file)
        XCTAssertEqual(StatusLineRunner.chainedCommand(), "~/bin/my-status.sh")

        try HooksInstaller.uninstall(settings: file)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), text)
        XCTAssertNil(StatusLineRunner.chainedCommand())
    }

    func testUpgradingAnOutdatedInstallKeepsFileOrder() throws {
        // settings.json where every hook is ours, from a version without the status line.
        var old = try HooksInstaller.addingOurs(to: try JSONValue.parse(Data(#"{"a": 1}"#.utf8)), chain: nil).root
        old["statusLine"] = nil
        old["zzz"] = .string("after hooks")
        XCTAssertEqual(HooksInstaller.status(of: old), .outdated)

        let upgraded = try HooksInstaller.addingOurs(to: old, chain: nil).root
        XCTAssertEqual(HooksInstaller.status(of: upgraded), .installed)
        XCTAssertEqual(upgraded.members?.map(\.key), ["a", "hooks", "zzz", "statusLine"])
        XCTAssertEqual(upgraded["hooks"]?.members?.map(\.key), old["hooks"]?.members?.map(\.key))
    }

    func testHooksWithoutStatusLineAreOutdated() throws {
        var root = try HooksInstaller.addingOurs(to: .object([]), chain: nil).root
        root["statusLine"] = nil
        XCTAssertEqual(HooksInstaller.status(of: root), .outdated)
    }

    func testDoesNotTouchUnparseableFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{ broken".utf8).write(to: file)
        XCTAssertThrowsError(try HooksInstaller.install(settings: file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ broken")
    }
}
