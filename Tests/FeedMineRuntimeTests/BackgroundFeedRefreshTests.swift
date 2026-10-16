import Foundation
import XCTest
@testable import FeedMineRuntime

private actor BackgroundAttemptRecorder {
    private(set) var operations = 0
    private(set) var commits = 0
    func entered() { operations += 1 }
    func committed() { commits += 1 }
}

final class BackgroundFeedRefreshTests: XCTestCase {
    func testDeniedOpportunityNeverInvokesPipelineOrCommits() async {
        let record = BackgroundAttemptRecorder()
        let result = await BackgroundFeedRefresh.run(allowed: { false }, opportunity: {
            await record.entered()
            await record.committed()
            return true
        })
        let operations = await record.operations
        let commits = await record.commits
        XCTAssertFalse(result)
        XCTAssertEqual(operations, 0)
        XCTAssertEqual(commits, 0)
    }

    func testGrantedOpportunityCallsOnlyInjectedExistingPipeline() async {
        let record = BackgroundAttemptRecorder()
        let result = await BackgroundFeedRefresh.run(allowed: { true }, opportunity: {
            await record.entered()
            return true
        })
        let operations = await record.operations
        let commits = await record.commits
        XCTAssertTrue(result)
        XCTAssertEqual(operations, 1)
        XCTAssertEqual(commits, 0)
    }

    func testCancelledBeforeGrantCannotRunPipeline() async {
        let record = BackgroundAttemptRecorder()
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await BackgroundFeedRefresh.run(allowed: { true }, opportunity: {
                await record.entered()
                return true
            })
        }.value
        let operations = await record.operations
        XCTAssertFalse(result)
        XCTAssertEqual(operations, 0)
    }

    func testExpirationDuringCooperativeWorkStopsBeforeCommitBoundary() async {
        let started = AsyncStream<Void>.makeStream()
        let resume = AsyncStream<Void>.makeStream()
        let record = BackgroundAttemptRecorder()
        let worker = Task {
            await BackgroundFeedRefresh.run(allowed: { true }, opportunity: {
                await record.entered()
                started.continuation.yield(())
                for await _ in resume.stream { break }
                guard !Task.isCancelled else { return false }
                await record.committed()
                return true
            })
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        worker.cancel()
        resume.continuation.yield(())
        let completed = await worker.value
        started.continuation.finish()
        resume.continuation.finish()
        let operations = await record.operations
        let commits = await record.commits
        XCTAssertFalse(completed)
        XCTAssertEqual(operations, 1)
        XCTAssertEqual(commits, 0)
    }
}
