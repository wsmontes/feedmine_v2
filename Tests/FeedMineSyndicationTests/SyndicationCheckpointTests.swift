import Foundation
import XCTest
import FeedMineAcquisition
import FeedMineSyndication

final class SyndicationCheckpointTests: XCTestCase {
    private func state(etag: String? = nil, modified: String? = nil, fingerprint: String? = nil, index: Int = 0) -> SyndicationCheckpointState? {
        .init(etag: etag,lastModified: modified,documentFingerprint: fingerprint,nextItemIndex: index)
    }
    private func envelope(_ data: Data, schema: UInt64 = 1, version: String = "feedmine-syndication/1-feedkit/10.9.4") -> AcquisitionCheckpoint {
        .init(blob: data,serializationSchema: schema,connectorVersion: version)!
    }
    func test26EmptyState() {
        let empty = SyndicationCheckpointCodec.empty
        XCTAssertNil(empty.etag); XCTAssertNil(empty.lastModified); XCTAssertNil(empty.documentFingerprint); XCTAssertEqual(empty.nextItemIndex,0)
    }
    func test27ValidatorOnly() {
        XCTAssertNotNil(state(etag: " ETag ")); XCTAssertNotNil(state(modified: " Date "))
        XCTAssertNotNil(state(etag: " ",modified: " "))
    }
    func test28PartialDocument() {
        let value = state(etag: "opaque",modified: "opaque",fingerprint: " fingerprint ",index: 3)!
        XCTAssertEqual(value.documentFingerprint," fingerprint "); XCTAssertEqual(value.nextItemIndex,3)
    }
    func test29InvalidPartialPairs() {
        XCTAssertNil(state(index: 1)); XCTAssertNil(state(fingerprint: "f")); XCTAssertNil(state(index: -1))
    }
    func test30EmptyStrings() {
        XCTAssertNil(state(etag: "")); XCTAssertNil(state(modified: "")); XCTAssertNil(state(fingerprint: "",index: 1))
        XCTAssertNotNil(state(etag: " ",modified: " ",fingerprint: " ",index: 1))
    }
    func test31CodecRoundtrip() throws {
        for value in [SyndicationCheckpointCodec.empty,state(etag: " W/\"Exact\" ",modified: " exact e\u{301} ")!,state(fingerprint: "opaque",index: 7)!] {
            let decoded = try SyndicationCheckpointCodec.decode(SyndicationCheckpointCodec.encode(value))
            XCTAssertEqual(decoded,value)
            XCTAssertEqual(decoded.lastModified.map { Array($0.utf8) },value.lastModified.map { Array($0.utf8) })
        }
    }
    func test32DeterministicBlob() throws {
        let value = state(etag: "z",modified: "a",fingerprint: "f",index: 7)!
        XCTAssertEqual(try SyndicationCheckpointCodec.encode(value).blob,try SyndicationCheckpointCodec.encode(value).blob)
        XCTAssertEqual(String(data: try SyndicationCheckpointCodec.encode(value).blob,encoding: .utf8),
            "{\"documentFingerprint\":\"f\",\"etag\":\"z\",\"lastModified\":\"a\",\"nextItemIndex\":7}")
    }
    func test33ExactEnvelope() throws {
        let encoded = try SyndicationCheckpointCodec.encode(SyndicationCheckpointCodec.empty)
        XCTAssertEqual(encoded.serializationSchema,1)
        XCTAssertEqual(encoded.connectorVersion,"feedmine-syndication/1-feedkit/10.9.4")
    }
    func test34WrongSchema() {
        XCTAssertThrowsError(try SyndicationCheckpointCodec.decode(envelope(Data(),schema: 2))) {
            XCTAssertEqual($0 as? SyndicationCheckpointError,.unsupportedSchema(2))
        }
    }
    func test35WrongConnectorVersion() {
        XCTAssertThrowsError(try SyndicationCheckpointCodec.decode(envelope(Data(),version: "other"))) {
            XCTAssertEqual($0 as? SyndicationCheckpointError,.unsupportedConnectorVersion("other"))
        }
    }
    func test36MalformedBlobAndInvalidDecodedState() {
        for text in ["not json","{}","{\"nextItemIndex\":-1}","{\"nextItemIndex\":1}","{\"documentFingerprint\":\"f\",\"nextItemIndex\":0}",
            "{\"etag\":\"\",\"nextItemIndex\":0}","{\"lastModified\":\"\",\"nextItemIndex\":0}","{\"documentFingerprint\":\"\",\"nextItemIndex\":1}","{\"nextItemIndex\":\"1\"}"] {
            XCTAssertThrowsError(try SyndicationCheckpointCodec.decode(envelope(Data(text.utf8)))) {
                XCTAssertEqual($0 as? SyndicationCheckpointError,.malformed)
            }
        }
        XCTAssertThrowsError(try JSONDecoder().decode(SyndicationCheckpointState.self,from: Data("{\"nextItemIndex\":1}".utf8)))
    }
}
