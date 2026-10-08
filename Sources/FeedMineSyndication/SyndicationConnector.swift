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
        var context = FeedConnectorExecutionContext()
        return try await pull(request, context: &context)
    }

    public func pull(_ request: FeedConnectorPull, context: inout FeedConnectorExecutionContext) async throws -> FeedConnectorEvent {
        do { return try await pullDocument(request, context: &context) }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as URLError where Self.isTransportFailure(error.code) {
            throw ConnectorOperationalFailure.transport
        }
        catch SyndicationHTTPError.unexpectedStatus { throw ConnectorOperationalFailure.remoteResponse }
        catch SyndicationHTTPError.nonHTTPResponse { throw ConnectorOperationalFailure.remoteResponse }
        catch SyndicationTranslationError.parseFailed { throw ConnectorOperationalFailure.remoteContent }
    }

    private static func isTransportFailure(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
            .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed,
            .serverCertificateHasBadDate, .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return true
        default: return false
        }
    }

    private struct AcquiredDocument: Sendable {
        let targetID: AcquisitionTargetID
        let generation: UInt64
        let document: SyndicationHTTPDocument
        let fingerprint: String
    }

    private func pullDocument(_ request: FeedConnectorPull, context: inout FeedConnectorExecutionContext) async throws -> FeedConnectorEvent {
        try Task.checkCancellation()
        guard request.targetID == configuration.targetID else {
            throw SyndicationConnectorError.targetMismatch(expected: configuration.targetID, actual: request.targetID)
        }
        let oldState = try request.checkpoint.map(SyndicationCheckpointCodec.decode) ?? SyndicationCheckpointCodec.empty
        let observedAt = now()
        guard observedAt.timeIntervalSince1970.isFinite else { throw SyndicationConnectorError.invalidObservedAt }
        let acquired: AcquiredDocument
        let transportByteCount: Int
        if let retained = context.retainedValue as? AcquiredDocument,
            retained.targetID == request.targetID, retained.generation == request.targetGeneration {
            acquired = retained
            transportByteCount = 0
            guard retained.document.body.count <= request.byteCapacity else {
                throw SyndicationHTTPError.bodyTooLarge(limit: request.byteCapacity, actualAtLeast: retained.document.body.count)
            }
        } else {
            context.retainedValue = nil
            let outcome = try await http.fetch(endpoint: configuration.endpoint, checkpoint: oldState,
                bodyByteCapacity: request.byteCapacity)
            guard case .document(let document) = outcome else { return .upToDate }
            acquired = AcquiredDocument(targetID: request.targetID, generation: request.targetGeneration,
                document: document, fingerprint: syndicationBodyFingerprint(document.body))
            transportByteCount = document.body.count
            context.retainedValue = acquired
        }
        try Task.checkCancellation()
        let document = acquired.document, fingerprint = acquired.fingerprint
        let matches = oldState.documentFingerprint.map { $0.utf8.elementsEqual(fingerprint.utf8) } ?? false
        // A matching completed document is settled before parsing or constructing observations.
        if matches && oldState.nextItemIndex == 0 { return .upToDate }
        let translation = try SyndicationTranslator().translate(data: document.body, configuration: configuration,
            observedAt: observedAt, startIndex: matches ? oldState.nextItemIndex : 0,
            itemCapacity: request.observationCapacity)
        guard let nextState = SyndicationCheckpointState(
            etag: document.redirectCount == 0 ? document.etag : nil,
            lastModified: document.redirectCount == 0 ? document.lastModified : nil,
            documentFingerprint: fingerprint,
            nextItemIndex: translation.nextItemIndex ?? 0) else { throw SyndicationConnectorError.invalidBatch }
        let delta = nextState == oldState ? nil : try SyndicationCheckpointCodec.encode(nextState)
        guard !translation.observations.isEmpty || delta != nil else { return .upToDate }
        guard let batch = AcquisitionBatch(targetID: request.targetID, targetGeneration: request.targetGeneration,
            expectedCheckpointRevision: request.checkpointRevision, observations: translation.observations,
            nextCheckpoint: delta) else { throw SyndicationConnectorError.invalidBatch }
        return .batch(batch, transportByteCount: transportByteCount)
    }
}
