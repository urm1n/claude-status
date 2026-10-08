import XCTest
@testable import StatusCore

final class InstallerTests: XCTestCase {
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

        let installed = try HooksInstaller.addingOurs(to: root)
        XCTAssertEqual(HooksInstaller.status(of: installed), .installed)

        // The other tool's Stop hook is kept, and ours is appended after it.
        let stop = installed["hooks"]?["Stop"]?.array
        XCTAssertEqual(stop?.count, 2)
        XCTAssertEqual(stop?.first, root["hooks"]?["Stop"]?.array?.first)
        // Unrelated keys keep their order.
        XCTAssertEqual(installed.members?.map(\.key), root.members?.map(\.key))

        // Installing twice doesn't duplicate.
        XCTAssertEqual(try HooksInstaller.addingOurs(to: installed), installed)

        XCTAssertEqual(HooksInstaller.removingOurs(from: installed), root)
    }

    func testUninstallDropsHooksKeyItCreated() throws {
        let root = try JSONValue.parse(Data(#"{"model": "opus"}"#.utf8))
        let installed = try HooksInstaller.addingOurs(to: root)
        XCTAssertEqual(HooksInstaller.removingOurs(from: installed), root)
    }

    func testOutdatedDetection() throws {
        var root = try HooksInstaller.addingOurs(to: .object([]))
        var hooks = root["hooks"]!
        hooks["StopFailure"] = nil
        root["hooks"] = hooks
        XCTAssertEqual(HooksInstaller.status(of: root), .outdated)
    }

    func testRefusesUnexpectedShapes() {
        XCTAssertThrowsError(try HooksInstaller.addingOurs(to: .array([])))
        XCTAssertThrowsError(try HooksInstaller.addingOurs(to: .object([JSONMember("hooks", .string("x"))])))
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

    func testDoesNotTouchUnparseableFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("{ broken".utf8).write(to: file)
        XCTAssertThrowsError(try HooksInstaller.install(settings: file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ broken")
    }
}
