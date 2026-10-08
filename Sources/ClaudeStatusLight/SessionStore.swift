import Foundation
import StatusCore

/// Mirrors `~/.claude-status-light/sessions/` in memory.
///
/// Everything is event driven, nothing polls:
/// - a vnode watcher on the folder fires when a hook writes or deletes a session file,
/// - a process-exit watcher per session removes it when its Claude process goes away,
/// - one one-shot timer fires at the next "stuck working" deadline, if any.
@MainActor
final class SessionStore {
    enum Event {
        case finished(key: String, SessionRecord)
        case needsInput(key: String, SessionRecord)
        case resumed(key: String, SessionRecord)
        case ended(key: String)
    }

    private(set) var records: [String: SessionRecord] = [:]
    var onChange: (() -> Void)?
    var onEvent: ((Event) -> Void)?

    private var dirSource: DispatchSourceFileSystemObject?
    private var processSources: [String: (pid: Int32, source: DispatchSourceProcess)] = [:]
    private var transcriptSources: [String: (path: String, source: DispatchSourceFileSystemObject)] = [:]
    private var pendingInterruptChecks: [String: DispatchWorkItem] = [:]
    private var timeoutTimer: DispatchSourceTimer?
    private var cache: [String: (modified: Date, record: SessionRecord)] = [:]
    private var hasLoaded = false

    /// Sessions without a known Claude process are dropped after this long with no events.
    private let orphanLifetime: TimeInterval = 12 * 60 * 60

    func start() {
        watchDirectory()
        reload()
    }

    // MARK: Derived state

    func effectiveState(_ record: SessionRecord, now: Double = Date().timeIntervalSince1970) -> SessionState {
        if record.state == .working, now - record.updatedAt >= Pref.idleTimeout { return .ready }
        return record.state
    }

    /// Highest priority across sessions: needs input > working > ready. nil = no sessions (gray).
    var aggregateState: SessionState? {
        let now = Date().timeIntervalSince1970
        return records.values.map { effectiveState($0, now: now) }.max { $0.priority < $1.priority }
    }

    var sortedSessions: [(key: String, record: SessionRecord, state: SessionState)] {
        let now = Date().timeIntervalSince1970
        return records.map { ($0.key, $0.value, effectiveState($0.value, now: now)) }
            .sorted {
                if $0.state.priority != $1.state.priority { return $0.state.priority > $1.state.priority }
                return $0.record.folderName.localizedStandardCompare($1.record.folderName) == .orderedAscending
            }
    }

    // MARK: Watching

    private func watchDirectory() {
        dirSource?.cancel()
        dirSource = nil
        try? FileManager.default.createDirectory(at: Paths.sessionsDir, withIntermediateDirectories: true)
        let fd = open(Paths.sessionsDir.path, O_EVTONLY)
        guard fd >= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                MainActor.assumeIsolated { self?.start() }
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.dirSource else { return }
                // The folder itself was deleted or moved (e.g. user cleaned up): start over.
                if !source.data.isDisjoint(with: [.delete, .rename]) { self.watchDirectory() }
                self.reload()
            }
        }
        source.setCancelHandler { close(fd) }
        dirSource = source
        source.resume()
    }

    func reload() {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        let urls = (try? fm.contentsOfDirectory(at: Paths.sessionsDir,
                                                includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        var fresh: [String: SessionRecord] = [:]
        var freshCache: [String: (modified: Date, record: SessionRecord)] = [:]

        for url in urls where url.pathExtension == "json" {
            let key = url.deletingPathExtension().lastPathComponent
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let record: SessionRecord
            if let cached = cache[key], cached.modified == modified {
                record = cached.record
            } else if let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode(SessionRecord.self, from: data) {
                record = decoded
            } else {
                continue
            }

            if let pid = record.claudePid {
                guard ProcessTree.isAlive(pid: pid, startTime: record.claudePidStart) else {
                    try? fm.removeItem(at: url) // terminal closed / Claude crashed
                    continue
                }
                watchProcess(key: key, pid: pid)
            } else if now - record.updatedAt > orphanLifetime {
                try? fm.removeItem(at: url)
                continue
            }
            fresh[key] = record
            freshCache[key] = (modified, record)
        }

        for (key, entry) in processSources where fresh[key] == nil {
            entry.source.cancel()
            processSources[key] = nil
        }

        if hasLoaded { emitTransitions(from: records, to: fresh) }
        hasLoaded = true
        records = fresh
        cache = freshCache
        updateTranscriptWatchers()
        scheduleTimeout()
        onChange?()
    }

    private func emitTransitions(from old: [String: SessionRecord], to new: [String: SessionRecord]) {
        for (key, record) in new {
            let previous = old[key]
            guard previous != record else { continue }
            let turnEnded = (record.lastEvent == "Stop" || record.lastEvent == "StopFailure")
                && record.finishedAt != nil && record.finishedAt != previous?.finishedAt
            if turnEnded {
                onEvent?(.finished(key: key, record))
            } else if record.state == .needsInput, previous?.state != .needsInput {
                onEvent?(.needsInput(key: key, record))
            } else if record.state == .working,
                      previous?.state != .working || record.turnStartedAt != previous?.turnStartedAt {
                onEvent?(.resumed(key: key, record))
            } else if record.lastEvent == HookReducer.interruptedEvent, previous?.lastEvent != record.lastEvent {
                onEvent?(.resumed(key: key, record)) // the user stopped Claude: clear its notifications
            }
        }
        for key in old.keys where new[key] == nil {
            onEvent?(.ended(key: key))
        }
    }

    // MARK: Interrupts (Esc)

    /// No hook fires when the user stops Claude, so while a session is working or waiting,
    /// watch its transcript and look for Claude Code's interrupt marker after each write.
    private func updateTranscriptWatchers() {
        for (key, watcher) in transcriptSources {
            let record = records[key]
            if record == nil || record?.state == .ready || record?.transcriptPath != watcher.path {
                watcher.source.cancel()
                transcriptSources[key] = nil
                pendingInterruptChecks.removeValue(forKey: key)?.cancel()
            }
        }
        for (key, record) in records where record.state != .ready && transcriptSources[key] == nil {
            guard let path = record.transcriptPath else { continue }
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleInterruptCheck(key) }
            }
            source.setCancelHandler { close(fd) }
            transcriptSources[key] = (path, source)
            source.resume()
            scheduleInterruptCheck(key) // it may have happened before we started watching
        }
    }

    /// Transcripts get many writes while Claude streams; check once things settle.
    private func scheduleInterruptCheck(_ key: String) {
        pendingInterruptChecks[key]?.cancel()
        let check = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkForInterrupt(key) }
        }
        pendingInterruptChecks[key] = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: check)
    }

    private func checkForInterrupt(_ key: String) {
        pendingInterruptChecks[key] = nil
        guard let record = records[key], record.state != .ready, let path = record.transcriptPath,
              let interruptedAt = TranscriptTail.interruptTime(URL(fileURLWithPath: path)),
              interruptedAt > record.stateSince else { return } // an older marker, from before this turn
        // Writes the session file; the folder watcher then reloads and turns the light green.
        HookRunner.markInterrupted(fileKey: key, ifUpdatedAt: record.updatedAt)
    }

    private func watchProcess(key: String, pid: Int32) {
        if processSources[key]?.pid == pid { return }
        processSources[key]?.source.cancel()
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.records[key]?.claudePid == pid else { return }
                try? FileManager.default.removeItem(at: Paths.sessionsDir.appendingPathComponent(key + ".json"))
                self.reload()
            }
        }
        processSources[key] = (pid, source)
        source.resume()
    }

    /// One timer, armed only while some session is "working", firing when the earliest one goes stale.
    func scheduleTimeout() {
        timeoutTimer?.cancel()
        timeoutTimer = nil
        let now = Date().timeIntervalSince1970
        let timeout = Pref.idleTimeout
        guard let next = records.values
            .filter({ $0.state == .working })
            .map({ $0.updatedAt + timeout })
            .filter({ $0 > now })
            .min() else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + (next - now) + 0.5, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleTimeout()
                self?.onChange?()
            }
        }
        timeoutTimer = timer
        timer.resume()
    }

    func removeAll() {
        for key in records.keys {
            try? FileManager.default.removeItem(at: Paths.sessionsDir.appendingPathComponent(key + ".json"))
        }
        reload()
    }
}
