// Connector-specific configuration; transport and durable generation authority are not owned here.
import Foundation
import FeedMineDomain
import FeedMineAcquisition

public struct SyndicationTargetConfiguration: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let endpoint: URL
    public let memberships: [AcquisitionMembershipClaim]

    public init?(targetID: AcquisitionTargetID, endpoint: URL, memberships: [AcquisitionMembershipClaim]) {
        guard let scheme = endpoint.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = endpoint.host, !host.isEmpty, endpoint.user == nil, endpoint.password == nil,
            !memberships.isEmpty, Set(memberships.map(\.sourceID)).count == memberships.count else { return nil }
        self.targetID = targetID
        self.endpoint = endpoint
        self.memberships = memberships
    }
}

public enum SyndicationConnectorError: Error, Equatable, Sendable {
    case targetMismatch(expected: AcquisitionTargetID, actual: AcquisitionTargetID)
    case invalidObservedAt
    case invalidBatch
}

public struct SyndicationConnector: FeedConnector, Sendable {
    private let configuration: SyndicationTargetConfiguration
    private let http: SyndicationHTTPClient
    private let now: @Sendable () -> Date

    public init?(configuration: SyndicationTargetConfiguration, session: URLSession, redirectCapacity: Int,
        now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(configuration: configuration, redirectCapacity: redirectCapacity, now: now,
            transport: URLSessionSyndicationHTTPTransport(session: session))
    }

    internal init?(configuration: SyndicationTargetConfiguration, redirectCapacity: Int,
        now: @escaping @Sendable () -> Date, transport: any SyndicationHTTPTransport) {
        guard redirectCapacity >= 0 else { return nil }
        self.configuration = configuration
        self.http = SyndicationHTTPClient(transport: transport, redirectCapacity: redirectCapacity)
        self.now = now
    }

    public func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        guard request.targetID == configuration.targetID else {
            throw SyndicationConnectorError.targetMismatch(expected: configuration.targetID, actual: request.targetID)
        }
        let oldState = try request.checkpoint.map(SyndicationCheckpointCodec.decode) ?? SyndicationCheckpointCodec.empty
        let observedAt = now()
        guard observedAt.timeIntervalSince1970.isFinite else { throw SyndicationConnectorError.invalidObservedAt }
        let outcome = try await http.fetch(endpoint: configuration.endpoint, checkpoint: oldState,
            bodyByteCapacity: request.byteCapacity)
        guard case .document(let document) = outcome else { return .upToDate }
        let fingerprint = syndicationBodyFingerprint(document.body)
        let matches = oldState.documentFingerprint.map { $0.utf8.elementsEqual(fingerprint.utf8) } ?? false
        let translation = try SyndicationTranslator().translate(data: document.body, configuration: configuration,
            observedAt: observedAt, startIndex: matches ? oldState.nextItemIndex : 0,
            itemCapacity: request.observationCapacity)
        guard let nextState = SyndicationCheckpointState(
            etag: document.redirectCount == 0 ? document.etag : nil,
            lastModified: document.redirectCount == 0 ? document.lastModified : nil,
            documentFingerprint: translation.nextItemIndex == nil ? nil : fingerprint,
            nextItemIndex: translation.nextItemIndex ?? 0) else { throw SyndicationConnectorError.invalidBatch }
        let delta = nextState == oldState ? nil : try SyndicationCheckpointCodec.encode(nextState)
        guard !translation.observations.isEmpty || delta != nil else { return .upToDate }
        guard let batch = AcquisitionBatch(targetID: request.targetID, targetGeneration: request.targetGeneration,
            expectedCheckpointRevision: request.checkpointRevision, observations: translation.observations,
            nextCheckpoint: delta) else { throw SyndicationConnectorError.invalidBatch }
        return .batch(batch, transportByteCount: document.body.count)
    }
}
