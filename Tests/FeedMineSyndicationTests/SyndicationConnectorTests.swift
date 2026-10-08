import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition
@testable import FeedMineSyndication

final class SyndicationConnectorTests: XCTestCase {
    private let target = AcquisitionTargetID()
    private let source = SourceID()
    private let clock = Date(timeIntervalSince1970:12345.125)
    private var configuration: SyndicationTargetConfiguration {
        .init(targetID:target,endpoint:URL(string:"https://example.test/feed")!,memberships:[.init(sourceID:source,kind:.direct)])!
    }
    private func rss(_ ids:[String]) -> Data {
        Data(("<rss version=\"2.0\"><channel><title>Feed</title>"+ids.map { "<item><guid>"+$0+"</guid></item>" }.joined()+"</channel></rss>").utf8)
    }
    private func hop(_ body:Data,etag:String? = nil,modified:String? = nil) -> SyndicationHTTPHop {
        .init(statusCode:200,location:nil,etag:etag,lastModified:modified,body:body)
    }
    private func pull(checkpoint:AcquisitionCheckpoint? = nil,capacity:Int = 10,revision:UInt64 = 42,
        target:AcquisitionTargetID? = nil) -> FeedConnectorPull {
        .init(targetID:target ?? self.target,targetGeneration:7,checkpointRevision:revision,checkpoint:checkpoint,
            observationCapacity:capacity,byteCapacity:100_000)!
    }
    private func connector(_ transport:ScriptedSyndicationTransport,now:Date? = nil) -> SyndicationConnector {
        let date = now ?? clock
        return .init(configuration:configuration,redirectCapacity:2,now:{ date },transport:transport)!
    }
    private func batch(_ event:FeedConnectorEvent,body:Data,file:StaticString = #filePath,line:UInt = #line) throws -> AcquisitionBatch {
        guard case .batch(let batch,let count) = event else { XCTFail("Expected batch",file:file,line:line); throw URLError(.badServerResponse) }
        XCTAssertEqual(count,body.count,file:file,line:line)
        XCTAssertEqual(batch.targetID,target,file:file,line:line); XCTAssertEqual(batch.targetGeneration,7,file:file,line:line)
        return batch
    }
    private func state(_ batch:AcquisitionBatch) throws -> SyndicationCheckpointState {
        try SyndicationCheckpointCodec.decode(XCTUnwrap(batch.nextCheckpoint))
    }
    func test17DirectRSSBatchExactStamp() async throws {
        let body = rss(["a"]),t = ScriptedSyndicationTransport([hop(rss(["a"]))])
        let request = pull(); let b = try batch(await connector(t).pull(request),body:body)
        XCTAssertEqual(b.expectedCheckpointRevision,request.checkpointRevision)
        XCTAssertEqual(b.observations.map(\.objectIdentity.value),["a"])
        XCTAssertEqual(b.observations[0].memberships,configuration.memberships)
        XCTAssertNotNil(b.nextCheckpoint)
    }
    func test18ExactObservedClockAndInvalidClockFence() async throws {
        let body = rss(["a","b"]),t = ScriptedSyndicationTransport([hop(rss(["a","b"]))])
        let b = try batch(await connector(t).pull(pull()),body:body)
        XCTAssertEqual(b.observations.map(\.observedAt),[clock,clock])
        let invalid = ScriptedSyndicationTransport([])
        do { _ = try await connector(invalid,now:Date(timeIntervalSince1970:.nan)).pull(pull()); XCTFail("Expected clock fence") }
        catch { XCTAssertEqual(error as? SyndicationConnectorError,.invalidObservedAt) }
        let journal = await invalid.journal(); XCTAssertTrue(journal.isEmpty)
    }
    func test19DirectValidatorsCheckpoint() async throws {
        let body = rss(["a"]),t = ScriptedSyndicationTransport([hop(rss(["a"]),etag:"W/\"exact\"",modified:" exact date ")])
        let s = try state(batch(await connector(t).pull(pull()),body:body))
        XCTAssertEqual(s.etag,"W/\"exact\""); XCTAssertEqual(s.lastModified," exact date ")
        XCTAssertEqual(s.documentFingerprint, syndicationBodyFingerprint(body)); XCTAssertEqual(s.nextItemIndex,0)
    }
    func test20RedirectedValidatorsDiscarded() async throws {
        let body = rss(["a"])
        let redirect = SyndicationHTTPHop(statusCode:302,location:"/next",etag:nil,lastModified:nil,body:Data())
        let t = ScriptedSyndicationTransport([redirect,hop(body,etag:"final",modified:"date")])
        let b = try batch(await connector(t).pull(pull()),body:body); XCTAssertNotNil(b.nextCheckpoint)
        let old = try SyndicationCheckpointCodec.encode(.init(etag:"old",lastModified:nil,documentFingerprint:nil,nextItemIndex:0)!)
        let second = ScriptedSyndicationTransport([redirect,hop(body,etag:"final",modified:"date")])
        let s = try state(batch(await connector(second).pull(pull(checkpoint:old)),body:body))
        XCTAssertEqual(s.documentFingerprint, syndicationBodyFingerprint(body)); XCTAssertEqual(s.nextItemIndex, 0); XCTAssertNil(s.etag); XCTAssertNil(s.lastModified)
    }
    private func slices() async throws -> [AcquisitionBatch] {
        let body = rss(["a","b","c"]),t = ScriptedSyndicationTransport(Array(repeating:hop(rss(["a","b","c"]),etag:"e"),count:3))
        let c = connector(t)
        let a = try batch(await c.pull(pull(capacity:1)),body:body)
        let b = try batch(await c.pull(pull(checkpoint:a.nextCheckpoint,capacity:1)),body:body)
        let d = try batch(await c.pull(pull(checkpoint:b.nextCheckpoint,capacity:1)),body:body)
        return [a,b,d]
    }
    func test21FirstPartialSlice() async throws {
        let values = try await slices(); let s = try state(values[0])
        XCTAssertEqual(values[0].observations.map(\.objectIdentity.value),["a"])
        XCTAssertEqual(s.nextItemIndex,1); XCTAssertEqual(s.etag,"e")
        XCTAssertEqual(s.documentFingerprint,"sha256:b058ca42769d253e5234936c14fcb25c294f032edd60bd39ae438b23a755be10")
    }
    func test22SameBodyResumes() async throws {
        let values = try await slices()
        XCTAssertEqual(values[1].observations.map(\.objectIdentity.value),["b"])
        XCTAssertEqual(try state(values[1]).nextItemIndex,2)
        XCTAssertEqual(try state(values[1]).documentFingerprint,try state(values[0]).documentFingerprint)
    }
    func test23ThirdSliceFinishes() async throws {
        let values = try await slices(); let s = try state(values[2])
        XCTAssertEqual(values[2].observations.map(\.objectIdentity.value),["c"])
        XCTAssertEqual(s.documentFingerprint, syndicationBodyFingerprint(rss(["a","b","c"]))); XCTAssertEqual(s.nextItemIndex,0); XCTAssertEqual(s.etag,"e")
    }
    func test24ChangedBodyRestartsZero() async throws {
        let bodyA = rss(["a","b"]),bodyB = rss(["new","next"])
        let t = ScriptedSyndicationTransport([hop(bodyA),hop(bodyB)]),c = connector(t)
        let first = try batch(await c.pull(pull(capacity:1)),body:bodyA)
        let next = try batch(await c.pull(pull(checkpoint:first.nextCheckpoint,capacity:1)),body:bodyB)
        XCTAssertEqual(next.observations.map(\.objectIdentity.value),["new"])
        XCTAssertEqual(try state(next).nextItemIndex,1)
        XCTAssertNotEqual(try state(next).documentFingerprint,try state(first).documentFingerprint)
    }
    func test25PartialRequestUnconditional() async throws {
        let body = rss(["a","b"]),t = ScriptedSyndicationTransport([hop(rss(["a","b"]),etag:"e",modified:"m"),hop(rss(["a","b"]),etag:"e",modified:"m")])
        let c = connector(t),first = try batch(await c.pull(pull(capacity:1)),body:body)
        _ = try await c.pull(pull(checkpoint:first.nextCheckpoint,capacity:1))
        let journal = await t.journal(); XCTAssertNil(journal[1].value(forHTTPHeaderField:"If-None-Match")); XCTAssertNil(journal[1].value(forHTTPHeaderField:"If-Modified-Since"))
    }
    func test26FullBoundaryNextPullConditional304() async throws {
        let body = rss(["a"]),t = ScriptedSyndicationTransport([hop(rss(["a"]),etag:"e",modified:"m"),.init(statusCode:304,location:nil,etag:nil,lastModified:nil,body:Data())])
        let c = connector(t),first = try batch(await c.pull(pull(capacity:1)),body:body)
        let event = try await c.pull(pull(checkpoint:first.nextCheckpoint)); XCTAssertEqual(event,.upToDate)
        let journal = await t.journal(); XCTAssertEqual(journal[1].value(forHTTPHeaderField:"If-None-Match"),"e"); XCTAssertEqual(journal[1].value(forHTTPHeaderField:"If-Modified-Since"),"m")
    }
    func test27LegacyValidatorOnlyCheckpointGainsFingerprint() async throws {
        let body = rss(["a"]),old = try SyndicationCheckpointCodec.encode(.init(etag:"e",lastModified:"m",documentFingerprint:nil,nextItemIndex:0)!)
        let t = ScriptedSyndicationTransport([hop(body,etag:"e",modified:"m")])
        let b = try batch(await connector(t).pull(pull(checkpoint:old)),body:body); XCTAssertNotNil(b.nextCheckpoint); XCTAssertEqual(b.observations.count,1)
    }
    func test28ClearOldValidators() async throws {
        let body = rss([]),old = try SyndicationCheckpointCodec.encode(.init(etag:"old",lastModified:nil,documentFingerprint:nil,nextItemIndex:0)!)
        let t = ScriptedSyndicationTransport([hop(body)])
        let b = try batch(await connector(t).pull(pull(checkpoint:old)),body:body)
        XCTAssertEqual(try state(b).documentFingerprint, syndicationBodyFingerprint(body)); XCTAssertEqual(try state(b).nextItemIndex, 0); XCTAssertNil(try state(b).etag)
    }
    func test29ClearOldPartial() async throws {
        let body = rss([]),old = try SyndicationCheckpointCodec.encode(.init(etag:nil,lastModified:nil,documentFingerprint:"different",nextItemIndex:99)!)
        let t = ScriptedSyndicationTransport([hop(body)])
        let b = try batch(await connector(t).pull(pull(checkpoint:old)),body:body)
        XCTAssertEqual(try state(b).documentFingerprint, syndicationBodyFingerprint(body)); XCTAssertEqual(try state(b).nextItemIndex, 0); XCTAssertNil(try state(b).etag)
    }
    func test30CheckpointOnlyBatch() async throws {
        let body = rss([]),t = ScriptedSyndicationTransport([hop(rss([]),etag:"new")])
        let b = try batch(await connector(t).pull(pull()),body:body); XCTAssertTrue(b.observations.isEmpty); XCTAssertEqual(try state(b).etag,"new")
    }
    func test31EmptyDocumentCompletesThenIsUpToDate() async throws {
        let body = rss([]), t = ScriptedSyndicationTransport([hop(body),hop(body)]), c = connector(t)
        let first = try batch(await c.pull(pull()),body:body)
        XCTAssertTrue(first.observations.isEmpty)
        let event = try await c.pull(pull(checkpoint:first.nextCheckpoint)); XCTAssertEqual(event,.upToDate)
    }
    func test32ParseFailure() async {
        let t = ScriptedSyndicationTransport([hop(Data("malformed".utf8))])
        do { _ = try await connector(t).pull(pull()); XCTFail("Expected parse failure") }
        catch { XCTAssertEqual(error as? ConnectorOperationalFailure,.remoteContent) }
        let journal = await t.journal(); XCTAssertEqual(journal.count,1)
    }
    func test33IncompatibleCheckpointBeforeHTTP() async {
        for cp in [AcquisitionCheckpoint(blob:Data(),serializationSchema:2,connectorVersion:SyndicationCheckpointCodec.connectorVersion)!,
                   AcquisitionCheckpoint(blob:Data(),serializationSchema:1,connectorVersion:"other")!] {
            let t = ScriptedSyndicationTransport([])
            do { _ = try await connector(t).pull(pull(checkpoint:cp)); XCTFail("Expected checkpoint failure") }
            catch { XCTAssertTrue(error is SyndicationCheckpointError) }
            let journal = await t.journal(); XCTAssertTrue(journal.isEmpty)
        }
    }
    func test34TargetMismatchBeforeHTTP() async {
        let other = AcquisitionTargetID(),t = ScriptedSyndicationTransport([])
        do { _ = try await connector(t).pull(pull(target:other)); XCTFail("Expected target fence") }
        catch { XCTAssertEqual(error as? SyndicationConnectorError,.targetMismatch(expected:target,actual:other)) }
        let journal = await t.journal(); XCTAssertTrue(journal.isEmpty)
    }
    func test35RejectedPositionDoesNotRefill() async throws {
        let body = rss(["","valid"]),t = ScriptedSyndicationTransport([hop(rss(["","valid"])),hop(rss(["","valid"]))]),c = connector(t)
        let a = try batch(await c.pull(pull(capacity:1)),body:body)
        XCTAssertTrue(a.observations.isEmpty); XCTAssertEqual(try state(a).nextItemIndex,1)
        let b = try batch(await c.pull(pull(checkpoint:a.nextCheckpoint,capacity:1)),body:body)
        XCTAssertEqual(b.observations.map(\.objectIdentity.value),["valid"])
    }
    func test36JSONEmptyIDItemRejection() async throws {
        let body = Data("{\"version\":\"https://jsonfeed.org/version/1.1\",\"title\":\"Feed\",\"items\":[{\"id\":\"\",\"url\":\"https://example.test/item\",\"content_text\":\"text\"}]}".utf8)
        let translation = try SyndicationTranslator().translate(data:body,configuration:configuration,observedAt:clock,startIndex:0,itemCapacity:1)
        XCTAssertEqual(translation.rejections,[.init(index:0,reason:.missingStableIdentity)])
        let t = ScriptedSyndicationTransport([hop(body,etag:"e")])
        let b = try batch(await connector(t).pull(pull()),body:body); XCTAssertTrue(b.observations.isEmpty); XCTAssertEqual(try state(b).etag,"e")
    }
    func test37JSONMissingIDParseFailure() async {
        let body = Data("{\"version\":\"https://jsonfeed.org/version/1.1\",\"items\":[{\"url\":\"https://example.test/item\"}]}".utf8)
        let t = ScriptedSyndicationTransport([hop(body)])
        do { _ = try await connector(t).pull(pull()); XCTFail("Expected parseFailed") }
        catch { XCTAssertEqual(error as? ConnectorOperationalFailure,.remoteContent) }
    }
    func test38TransportByteCountExactFinalBody() async throws {
        let body = rss(["é"]),t = ScriptedSyndicationTransport([.init(statusCode:301,location:"/next",etag:nil,lastModified:nil,body:Data(repeating:0,count:50)),hop(body)])
        _ = try batch(await connector(t).pull(pull()),body:body)
    }
    func test39TransportFailureNoRetry() async {
        let t = ScriptedSyndicationTransport(error:URLError(.notConnectedToInternet))
        do { _ = try await connector(t).pull(pull()); XCTFail("Expected network failure") }
        catch { XCTAssertEqual(error as? ConnectorOperationalFailure,.transport) }
        let journal = await t.journal(); XCTAssertEqual(journal.count,1)
    }
    func test40CheckpointRevisionPreserved() async throws {
        let body = rss(["a"]),t = ScriptedSyndicationTransport([hop(rss(["a"]),etag:"new")])
        let b = try batch(await connector(t).pull(pull(revision:UInt64.max)),body:body)
        XCTAssertEqual(b.expectedCheckpointRevision,UInt64.max)
    }
}

extension SyndicationConnectorTests {
    func test3R2ExplicitOperationalMappingAndUnknownErrorsRemainFatal() async throws {
        for code in [500, 503] {
            let t = ScriptedSyndicationTransport([.init(statusCode: code, location: nil, etag: nil, lastModified: nil, body: Data())])
            do { _ = try await connector(t).pull(pull()); XCTFail("Expected remote response") }
            catch { XCTAssertEqual(error as? ConnectorOperationalFailure, .remoteResponse) }
        }
        for (error, expected) in [(URLError(.timedOut), ConnectorOperationalFailure.transport)] {
            let t = ScriptedSyndicationTransport(error: error)
            do { _ = try await connector(t).pull(pull()); XCTFail("Expected transport") }
            catch { XCTAssertEqual(error as? ConnectorOperationalFailure, expected) }
            let calls = await t.journal(); XCTAssertEqual(calls.count, 1)
        }
        let nonHTTP = ScriptedSyndicationTransport(error: SyndicationHTTPError.nonHTTPResponse)
        do { _ = try await connector(nonHTTP).pull(pull()); XCTFail("Expected nonHTTPResponse") }
        catch { XCTAssertEqual(error as? ConnectorOperationalFailure, .remoteResponse) }
        let unknown = ScriptedSyndicationTransport(error: URLError(.unsupportedURL))
        do { _ = try await connector(unknown).pull(pull()); XCTFail("Expected fatal unknown transport code") }
        catch { XCTAssertEqual((error as? URLError)?.code, .unsupportedURL) }
        let cancelled = ScriptedSyndicationTransport(error: URLError(.cancelled))
        do { _ = try await connector(cancelled).pull(pull()); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let limit = ScriptedSyndicationTransport(error: SyndicationHTTPError.bodyTooLarge(limit: 1, actualAtLeast: 2))
        do { _ = try await connector(limit).pull(pull()); XCTFail("Expected fatal byte limit") }
        catch { XCTAssertEqual(error as? SyndicationHTTPError, .bodyTooLarge(limit: 1, actualAtLeast: 2)) }
    }
}

extension SyndicationConnectorTests {
    func test3R3CompletedDocumentWithoutValidatorsIsUpToDateBeforeTranslation() async throws {
        let body = rss(["a"]), transport = ScriptedSyndicationTransport([hop(body),hop(body)])
        let first = try batch(await connector(transport).pull(pull()), body: body)
        let rebuilt = connector(transport)
        let second = try await rebuilt.pull(pull(checkpoint:first.nextCheckpoint))
        XCTAssertEqual(second, .upToDate)
        XCTAssertEqual(try state(first).documentFingerprint, syndicationBodyFingerprint(body))
        XCTAssertEqual(try state(first).nextItemIndex, 0)
        let requests = await transport.journal(); XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[1].value(forHTTPHeaderField:"If-None-Match"))
    }
}
