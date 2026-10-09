import Foundation
import StatusCore

/// Session (5-hour) and weekly usage, from whichever source is freshest:
/// - the status line data Claude Code hands to `csl-hook statusline` (terminal sessions, offline), or
/// - opt-in: the endpoint behind `/usage`, using Claude Code's own login (works for VS Code too).
@MainActor
final class UsageStore {
    private(set) var statusLine: UsageSnapshot?
    private(set) var fetched: UsageSnapshot?
    private(set) var fetchError: UsageFetcher.Failure?
    private(set) var isFetching = false
    var onChange: (() -> Void)?

    private var dirSource: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var resetTimer: DispatchSourceTimer?
    private var lastAttempt: Date = .distantPast
    private var active = false

    /// Re-fetch at most this often, and only while a Claude session is open.
    private let fetchInterval: TimeInterval = 5 * 60

    var current: UsageSnapshot? {
        [statusLine, fetched].compactMap { $0 }.max { $0.updatedAt < $1.updatedAt }
    }

    /// Current session usage (0 after the window resets), for the number next to the light.
    var sessionPercent: Int? {
        current?.session.map { Int($0.current(now: Date().timeIntervalSince1970).usedPercentage.rounded()) }
    }

    /// One-shot timer at the next reset, so the % next to the light drops to 0 on time.
    private func scheduleResetTimer() {
        resetTimer?.cancel()
        resetTimer = nil
        let now = Date().timeIntervalSince1970
        guard let next = current?.nextReset(after: now) else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + (next - now) + 1, leeway: .seconds(10))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        resetTimer = timer
        timer.resume()
    }

    private func changed() {
        scheduleResetTimer()
        onChange?()
    }

    var fetchEnabled: Bool { Pref.defaults.bool(forKey: Pref.fetchUsage) }

    func start() {
        watchDirectory()
        loadStatusLine()
    }

    // MARK: Status line source (file written by csl-hook)

    private func watchDirectory() {
        dirSource?.cancel()
        try? FileManager.default.createDirectory(at: Paths.usageDir, withIntermediateDirectories: true)
        let fd = open(Paths.usageDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.dirSource else { return }
                if !source.data.isDisjoint(with: [.delete, .rename]) { self.watchDirectory() }
                self.loadStatusLine()
            }
        }
        source.setCancelHandler { close(fd) }
        dirSource = source
        source.resume()
    }

    private func loadStatusLine() {
        let snapshot = (try? Data(contentsOf: Paths.statusLineUsageFile))
            .flatMap { try? JSONDecoder().decode(UsageSnapshot.self, from: $0) }
        guard snapshot != statusLine else { return }
        statusLine = snapshot
        changed()
    }

    // MARK: Anthropic source (opt-in)

    /// Called when sessions come and go: fetch periodically only while Claude is in use.
    func setActive(_ isActive: Bool) {
        guard isActive != active else { return }
        active = isActive
        scheduleTimer()
        if isActive { refresh() }
    }

    func settingChanged() {
        if fetchEnabled {
            fetchError = nil
            refresh(force: true)
        } else {
            fetched = nil
            fetchError = nil
            changed()
        }
        scheduleTimer()
    }

    /// Fetches unless it did so recently. A denied Keychain prompt is never re-shown on its own.
    func refresh(force: Bool = false) {
        guard fetchEnabled, !isFetching else { return }
        if !force {
            if Date().timeIntervalSince(lastAttempt) < 60 { return }
            if fetchError == .keychainDenied { return }
        }
        lastAttempt = Date()
        isFetching = true
        Task {
            let result = await Task.detached(priority: .utility) { await UsageFetcher.fetch() }.value
            self.isFetching = false
            switch result {
            case .success(let snapshot):
                self.fetched = snapshot
                self.fetchError = nil
            case .failure(let failure):
                self.fetchError = failure
            }
            self.changed()
        }
    }

    /// Claude Code renews its own login whenever it makes a request, so ask it for one tiny reply.
    /// (The app never touches the refresh token itself.)
    func renewLogin() {
        guard !isFetching else { return }
        isFetching = true
        Task {
            await Task.detached(priority: .utility) { UsageFetcher.renewLogin() }.value
            self.isFetching = false
            self.refresh(force: true)
        }
    }

    private func scheduleTimer() {
        timer?.cancel()
        timer = nil
        guard active, fetchEnabled else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + fetchInterval, repeating: fetchInterval, leeway: .seconds(30))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        self.timer = timer
        timer.resume()
    }
}

/// Reads the same numbers as Claude Code's `/usage`. The login token is read from the Keychain (via
/// `/usr/bin/security`, like Claude Code itself) for
/// each request and never stored, logged, refreshed, or sent anywhere but api.anthropic.com.
enum UsageFetcher {
    enum Failure: Error, Equatable {
        case notLoggedIn
        case keychainDenied
        case loginExpired
        case notSubscriber
        case http(Int)
        case network
        case unexpectedResponse

        var message: String {
            switch self {
            case .notLoggedIn: return "Claude Code isn’t logged in on this Mac"
            case .keychainDenied: return "Couldn’t read Claude Code’s login from the Keychain"
            case .loginExpired: return "Login expired: use Claude Code once to refresh it"
            case .notSubscriber: return "No usage limits on this account"
            case .http(let code): return "Anthropic returned an error (\(code))"
            case .network: return "Couldn’t reach Anthropic"
            case .unexpectedResponse: return "Unexpected response from Anthropic"
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    static func fetch() async -> Result<UsageSnapshot, Failure> {
        let token: String
        switch readToken() {
        case .success(let value): token = value
        case .failure(let failure): return .failure(failure)
        }

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-status-light", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .failure(.network) }
        switch http.statusCode {
        case 200: break
        case 401: return .failure(.loginExpired)
        case 403: return .failure(.notSubscriber)
        default: return .failure(.http(http.statusCode))
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.unexpectedResponse)
        }
        guard let snapshot = UsageSnapshot.fromAnthropic(json, now: Date().timeIntervalSince1970) else {
            return .failure(.notSubscriber)
        }
        return .success(snapshot)
    }

    /// Runs `claude -p` once so Claude Code refreshes its own login in the Keychain.
    static func renewLogin() {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          "\(home)/.claude/local/claude"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-p", "reply with ok", "--model", "haiku"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if process.isRunning { process.terminate() }
    }

    /// Claude Code stores `{"claudeAiOauth": {"accessToken", "expiresAt" (ms), …}}` as a generic password,
    /// written and read through Apple's `/usr/bin/security` tool, which is the only app on that item's
    /// access list. Reading it the same way means macOS never prompts, and it keeps working after app
    /// updates and after Claude Code refreshes its login (which resets the access list).
    private static func readToken() -> Result<String, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(.keychainDenied) }
        let raw = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        switch process.terminationStatus {
        case 0: break
        case 44: return .failure(.notLoggedIn) // errSecItemNotFound
        default: return .failure(.keychainDenied)
        }
        let data = decodePasswordOutput(raw)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return .failure(.notLoggedIn) }
        // Never refresh the token ourselves: that would rotate Claude Code's login out from under it.
        if let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           expiresAt / 1000 < Date().timeIntervalSince1970 {
            return .failure(.loginExpired)
        }
        return .success(token)
    }

    /// `security -w` prints the password as text, or as hex when it isn't printable.
    private static func decodePasswordOutput(_ raw: Data) -> Data {
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "{" { return Data(text.utf8) }
        guard text.count.isMultiple(of: 2), text.allSatisfy(\.isHexDigit) else { return Data(text.utf8) }
        var bytes = [UInt8]()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            bytes.append(UInt8(text[index..<next], radix: 16) ?? 0)
            index = next
        }
        return Data(bytes)
    }
}
