//
// File: RunwayTrace.swift
// Module: FeedMineApp (host)
//
// Responsibility:
// The facts F05 asks to be provable, written down where a run can be judged without asking the app how it feels:
// when content was published and admitted, when the reader advanced, when a runway opportunity started and
// finished, what happened to each candidate's media, and — for the replenishment chain — when supply was
// requested, when the data arrived and what destination concluded it. One JSON object per line, capped, and
// written **off the caller's thread** — a trace that blocks the feed is a trace that changes what it measures.
//
// It also records its **own** losses. A ceiling that swallows events in silence produces a run that looks like a
// run where nothing happened, and the oracle would read the absence as a fact about the product instead of a fact
// about the trace: `trace_truncated` states what was dropped, by cause, on the first drop and again at flush.
//
// Does not own: any decision. Nothing reads this to choose what to publish; it is evidence, not policy.
import Foundation
import FeedMineDomain
import FeedMineRuntime

/// Append-only evidence of what the feed actually did, with the clock that observed it.
///
/// The file outlives the process: a relaunch **appends** to the segment the previous launch wrote (the reopen gates
/// read it), and the line budget is a property of the file, not of a start — the count is seeded from what is
/// already there, so restarts cannot multiply it.
final class RunwayTrace: @unchecked Sendable {
    /// B03 walks 1.800 advances **and** records every examined candidate's readiness: the ceiling has to hold a
    /// thirty-minute trace, or the gate would fail for lack of evidence rather than for lack of content.
    ///
    /// 40.000 was sized against 1.800 advances and missed: run `20261021T033520Z` wrote **40.060** lines in 1.854 s
    /// (21,6 lines/s) with **2.944** advances, exhausted the budget just before the last advance and dropped the
    /// admission after it — which the oracle reads as a one-second stall (B03 FAIL). The arithmetic that fits the
    /// measured density: a 2.000 s acceptance window (30-minute gate + startup + flush) at 21,6 lines/s is 43.200
    /// lines; 64.000 holds that with ~45% headroom. At the measured 249 bytes/line it is ~16 MB on disk — bounded,
    /// and cheaper than a verdict produced by missing evidence.
    static let lineCeiling = 64_000
    /// The events a judgment reads: B03's advances and admissions, the readiness of every examined candidate, the
    /// reader position the reopen gates read, and `runway_completed` — the closure the journey instrument pairs with
    /// every `advance` (more openings than closures is read as an unfinished opportunity, so dropping the closure
    /// while keeping the opening would manufacture a lacuna). They may use the whole ceiling.
    private static let journeyEvents: Set<String> = ["advance", "admitted", "candidate", "position_checkpoint",
        "runway_completed"]
    /// The ceiling is partitioned: context events may not consume the last third. In the same measured run the
    /// journey facts were 16.671 of 40.060 lines, so the 21.333-line reserve covers that volume with margin; a budget
    /// that lets context crowd them out turns a dense run into a trace that cannot answer B03, which is exactly the
    /// failure the 40.000-line ceiling produced.
    private static let contextShare = 2.0 / 3.0
    /// Lines buffer in memory and leave in batches: measured, writing each line as it happens put file I/O on the
    /// main actor during publication, and the acceptance driver timed out on a UI query because of it.
    private static let batchSize = 64
    /// How often a loss may announce itself. The bound is what keeps the announcement from becoming the loss: the
    /// first drop of each kind is stated immediately, the totals are stated when the trace is flushed.
    private static let truncationNoticeCeiling = 8

    private struct Line: Encodable {
        /// Wall clock, kept because the oracle reads it and because a human reads the trace beside a log.
        let at: Double
        /// Monotonic uptime in seconds at the instant of recording. The intervals between requested → arrived →
        /// admitted are measured on **this** clock: a wall clock can step, and an interval measured across a step
        /// is not an interval.
        let mono: Double
        let event: String
        let fields: [String: String]
    }

    private let lock = NSLock()
    private let url: URL
    /// The instance's ceiling: the default is the documented one, and a test states a small one to prove the loss
    /// is recorded rather than silently absorbed.
    private let ceiling: Int
    /// How many lines context events may occupy before the journey's own reserve starts protecting the rest.
    private let contextCeiling: Int
    private let writer = DispatchQueue(label: "feedmine.runway-trace", qos: .utility)
    private var pending: [Data] = []
    /// Lines already in the file when this process opened it, plus the ones this process wrote. The ceiling is a
    /// property of the **file**, not of a process: a relaunch with a fresh budget would append another 64.000 lines
    /// to the same trace on every start. Seeded once in `init`, before the first `record` can read it.
    private var lines = 0
    /// Every line this trace has written, announcements included. The event budget above does not count a
    /// truncation notice, and a notice is still disk; this counter is what keeps the whole file (not only its
    /// events) bounded across restarts.
    private var fileLines = 0
    /// The previous process left a line unterminated: the first write must start a new one instead of gluing the
    /// two. Owned by the writer queue after `init` seeds it.
    private var needsLeadingNewline = false
    private var notices = 0
    /// Keys whose transition was already recorded.
    private var seen: Set<String> = []
    /// The one file handle every batch is written through. Owned by the writer's serial queue: created there, used
    /// there, never closed there.
    private var handle: FileHandle?
    /// Evidence of what this trace lost, by cause: an event the ceiling refused, one that could not be encoded, and
    /// one whose batch never reached the disk. Counted always, stated on the first loss and at flush.
    private var droppedByCeiling = 0
    /// Context events refused so the journey's reserve stayed available. Counted apart from the ceiling: this is a
    /// deliberate partition of the budget, and the announcement names it as such.
    private var droppedByContext = 0
    private var droppedByEncoding = 0
    private var droppedByWrite = 0
    /// The totals already stated, so a flush with nothing new to say stays silent.
    private var reportedDrops = 0

    init(directory: URL, name: String = "trace.jsonl", lineCeiling: Int = RunwayTrace.lineCeiling) {
        url = directory.appendingPathComponent(name)
        ceiling = max(1, lineCeiling)
        // A small ceiling still reserves at least one line, otherwise a test-sized budget would have no journey
        // guarantee at all. Context saturates first; the journey always has the rest.
        contextCeiling = max(1, Int(Double(ceiling) * Self.contextShare))
        // A trace belongs to a run, and a run outlives a process: the reopen gates read the segment the first
        // launch wrote, so a relaunch appends to the file instead of replacing it. The budget follows the file too
        // — the count is taken here, once, before any `record` consults it, so the ceiling, the context reserve
        // and the loss announcements stay per file across restarts. Reading is streaming and bounded; at the
        // measured 249 bytes/line the full 64.000-line trace is ~16 MB scanned once at startup.
        let existing = Self.existingContent(at: url)
        lines = existing.lines
        fileLines = existing.lines
        needsLeadingNewline = existing.tornTail
    }

    /// What the file already holds, read once in a streaming pass: the lines it carries and whether the last one
    /// was cut short. A process killed mid-write (`terminate`) can leave an unterminated tail; counting only `\n`
    /// would then glue the next launch's first line onto that partial JSON, and the oracle — which reads line by
    /// line — would lose both. The tail counts as a used line, and the first write starts on a fresh one.
    private static func existingContent(at url: URL) -> (lines: Int, tornTail: Bool) {
        guard let stream = InputStream(url: url) else { return (0, false) }
        stream.open()
        defer { stream.close() }
        var count = 0
        var lastByte: UInt8?
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            for index in 0..<read where buffer[index] == 0x0A { count += 1 }
            lastByte = buffer[read - 1]
        }
        let torn = lastByte.map { $0 != 0x0A } ?? false
        return (torn ? count + 1 : count, torn)
    }

    /// One event. `fields` are strings: the caller states what it knows, and the trace stays a document a script
    /// can read. A `Codable` payload is what makes a serialization failure catchable — `JSONSerialization` raises
    /// an Objective-C exception for a value it cannot write, which `try?` does not catch, and the app died on it.
    func record(_ event: String, _ fields: [String: String] = [:], at date: Date = Date()) {
        // The ceiling is checked **before** the encode: a caller in a view body can ask thousands of times, and
        // encoding what will be thrown away is work on the thread that is drawing the feed. The refusal is counted
        // and, the first time, stated: the ceiling must not swallow events in silence.
        lock.lock()
        guard lines < ceiling else {
            droppedByCeiling += 1
            let announce = droppedByCeiling == 1
            lock.unlock()
            if announce { notice("line_ceiling", at: date) }
            return
        }
        // Context may not spend the journey's reserve: an over-dense run loses telemetry, never the advance or the
        // admission that proves the feed kept moving. The refusal is counted and stated like any other loss.
        if !Self.journeyEvents.contains(event), lines >= contextCeiling {
            droppedByContext += 1
            let announce = droppedByContext == 1
            lock.unlock()
            if announce { notice("context_budget", at: date) }
            return
        }
        lines += 1
        fileLines += 1
        lock.unlock()
        let monotonic = ProcessInfo.processInfo.systemUptime
        guard let data = try? JSONEncoder().encode(Line(at: date.timeIntervalSince1970, mono: monotonic,
            event: event, fields: fields)) else {
            lock.lock()
            droppedByEncoding += 1
            let announce = droppedByEncoding == 1
            lock.unlock()
            if announce { notice("encoding", at: date) }
            return
        }
        lock.lock()
        pending.append(data)
        let batch = pending.count >= Self.batchSize ? pending : []
        if !batch.isEmpty { pending.removeAll(keepingCapacity: true) }
        lock.unlock()
        guard !batch.isEmpty else { return }
        write(batch)
    }

    /// A **transition**, recorded once per key: Codex's review pointed out that a level-triggered event fires again
    /// on every later query and therefore proves nothing about recovery. The first observation of a key is the
    /// transition; the rest are noise.
    func recordOnce(_ event: String, key: String, _ fields: [String: String] = [:], at date: Date = Date()) {
        lock.lock()
        let isFirst = seen.insert(key).inserted
        lock.unlock()
        guard isFirst else { return }
        record(event, fields, at: date)
    }

    /// What is buffered goes to disk now. The host calls it when the app leaves the foreground, so a trace that
    /// was cut short still says everything it saw. When this trace has lost events since the last time it said so,
    /// it says so here as well — the totals, one line, whatever the cause.
    func flush() {
        lock.lock()
        let unreported = droppedByCeiling + droppedByContext + droppedByEncoding + droppedByWrite - reportedDrops
        var batch = pending
        pending.removeAll(keepingCapacity: true)
        if unreported > 0, fileLines < ceiling + Self.truncationNoticeCeiling + 1,
            let data = truncationLine(reason: "flush_total") {
            fileLines += 1
            reportedDrops += unreported
            batch.append(data)
        }
        lock.unlock()
        guard !batch.isEmpty else { return }
        write(batch)
    }

    /// `flush`, then wait for the writer to have drained. The production path deliberately does not block; a test
    /// that read the file right after `flush()` would be racing the writer queue.
    func flushAndWait() {
        flush()
        writer.sync {}
    }

    /// The statement that this trace is no longer complete, written through the **same** buffer as the events so
    /// the file stays in order: everything recorded before the first drop reaches the disk with the announcement.
    private func notice(_ reason: String, at date: Date) {
        lock.lock()
        // The announcement is written even though the event budget is exhausted, so it needs its own hard bound:
        // `truncationNoticeCeiling` notices per process, and the whole file never passes
        // `ceiling + truncationNoticeCeiling + 1` lines, however many times the app is relaunched. At the cap the
        // announcements already in the file stand for the loss; the counters keep counting it.
        guard notices < Self.truncationNoticeCeiling,
            fileLines < ceiling + Self.truncationNoticeCeiling + 1,
            let data = truncationLine(reason: reason) else {
            lock.unlock()
            return
        }
        notices += 1
        fileLines += 1
        reportedDrops = droppedByCeiling + droppedByContext + droppedByEncoding + droppedByWrite
        pending.append(data)
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
        write(batch)
    }

    /// Caller holds `lock`.
    private func truncationLine(reason: String) -> Data? {
        try? JSONEncoder().encode(Line(at: Date().timeIntervalSince1970,
            mono: ProcessInfo.processInfo.systemUptime, event: ReplenishmentEvent.truncated,
            fields: ["reason": reason, "ceiling": String(ceiling),
                "dropped_by_ceiling": String(droppedByCeiling),
                "dropped_by_context": String(droppedByContext),
                "dropped_by_encoding": String(droppedByEncoding),
                "dropped_by_write": String(droppedByWrite),
                "written": String(lines)]))
    }

    private func countLostBatch(_ count: Int) {
        lock.lock()
        droppedByWrite += count
        lock.unlock()
    }

    private func write(_ batch: [Data]) {
        var payload = Data()
        for line in batch {
            payload.append(line)
            payload.append(0x0A)
        }
        writer.async { [url] in
            // **One** handle, opened once and never closed until the process ends, written through the **throwing**
            // API. `NSFileHandle.write(_:)` and `seekToEnd()` raise an Objective-C exception when the underlying
            // syscall fails — `try?` cannot catch that, so the app aborted mid-trace. Measured twice: a B03 died at
            // 193 s and again at 228 s with `_NSFileHandleRaiseOperationExceptionWhileReading` raised inside
            // `-[NSConcreteFileHandle writeData:]`. The second time the cause was visible: the host volume had
            // 464 MB free, so the write failed with ENOSPC and Foundation chose to raise. `write(contentsOf:)` and
            // `seekToEnd() throws` turn the same failure into a Swift error, which evidence may swallow and the
            // feed must survive.
            if self.handle == nil {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                // `createFile(contents: nil)` **truncates** an existing file (measured), and this is the first write
                // of each process: the reopen gates read what the previous launch wrote, so a relaunch must append,
                // not replace. Create only when there is nothing to append to.
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                self.handle = try? FileHandle(forWritingTo: url)
            }
            guard let handle = self.handle else {
                // No handle is not "nothing to write": these lines are gone, and the count is kept so that the next
                // write that does land states them. The limit is stated rather than hidden: when the destination
                // never becomes writable again, the announcement is the one thing that cannot land.
                self.countLostBatch(batch.count)
                return
            }
            _ = try? handle.seekToEnd()
            // A tail cut short by the previous process is not a line the oracle can read: start this batch on a
            // line of its own. The newline is only spent once the write lands, so a failed first write retries it.
            var outbound = payload
            if self.needsLeadingNewline { outbound.insert(0x0A, at: 0) }
            do {
                try handle.write(contentsOf: outbound)
                self.needsLeadingNewline = false
            } catch { self.countLostBatch(batch.count) }
        }
    }
}

#if DEBUG
/// The journey's own facts, spoken on the **device console**.
///
/// Why it exists: on a physical phone the console is the only channel a run has. The instrumented journey of
/// 2026-10-15 wrote 529 console lines in seven minutes — 523 of them per-second frame telemetry and **none** about
/// acquisition, contact or media — so a problem the owner reports would have arrived with no trace at all (the
/// screenshot route is closed on this Mac: `idevicescreenshot` cannot start `screenshotr` and no phone-mirroring
/// window exists). The console plus the container census is the route that works, and this is the console half.
///
/// Why it is not a state store: every number below is already owned elsewhere. The cards and their media kinds come
/// from the host's own published projection; the sources contacted and the ones that answered come from PD-3's
/// `PreparationProgress`, the pipeline-evidence value that exists for the preparation screen; the media counts come
/// from the media pipeline's own `MediaReadiness` index; the refused installations come from `FeedFlowCounters`.
/// This type only states them, once per second, and stores nothing.
///
/// Cost: nothing when the switch is off, and nothing at all in a shipping build — the switch is the same kind the
/// other debug instrumentation uses (`FEEDMINE_TRACE_CAPTURE`), it is read once, and the whole type is `#if DEBUG`.
enum FeedJourneyConsole {
    /// Off by default: the console is a channel, not a product surface. `scripts/device-journey.sh` launches the
    /// development app with it on.
    static let enabled = ProcessInfo.processInfo.environment["FEEDMINE_JOURNEY_CONSOLE"] == "1"

    /// One second's facts, as their owners hold them. The card counts are the reader's admitted window; the media
    /// counts are the media owner's own revisions — `prepared` carries a ready image, `settled` was decided at all,
    /// so a revision that is neither is still pending (F06).
    struct Facts {
        var elapsedSeconds: Double = 0
        var cards = 0
        var hero = 0
        var thumbnail = 0
        var textOnly = 0
        /// Cards of the admitted window whose pixels are ready to draw right now. Same unit as `hero`/`thumbnail`/
        /// `textOnly` — a card — so the pair the owner asks for ("declared media" versus "prepared media") is read
        /// on one line: a card that declares media (`hero + thumb`) and has no resident image is media that did not
        /// arrive. The two `media_*` counters below are the media pipeline's own numbers and are counted per
        /// revision, not per card; they are stated beside these and never compared as if they were the same unit.
        var mediaResident = 0
        var mediaPrepared = 0
        var mediaSettled = 0
        var sourcesContacted = 0
        var sourcesResponded = 0
        var sourcesUnreachable = 0
        /// Whether the source facts are still being observed (first-launch preparation) or are the last known
        /// values. A frozen count that reads as live is worse than no count.
        var preparationLive = false
        var installRejects = 0
    }

    /// One bounded line: the counts, never a stream of events and never a per-card id. The keys are the frame
    /// line's own style, so one `grep` finds both series.
    static func line(_ facts: Facts) -> String {
        "t=\(Int(facts.elapsedSeconds.rounded()))s cards=\(facts.cards)"
            + " hero=\(facts.hero) thumb=\(facts.thumbnail) text=\(facts.textOnly)"
            + " media_resident=\(facts.mediaResident)"
            + " media_prepared=\(facts.mediaPrepared) media_settled=\(facts.mediaSettled)"
            + " sources_contacted=\(facts.sourcesContacted) sources_responded=\(facts.sourcesResponded)"
            + " sources_unreachable=\(facts.sourcesUnreachable)"
            + " preparation=\(facts.preparationLive ? "live" : "done")"
            + " install_rejects=\(facts.installRejects)"
    }
}
#endif
