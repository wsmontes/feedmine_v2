// Finite external-source failure vocabulary; no durable integrity or cancellation semantics.
public enum ConnectorOperationalFailure: Error, Hashable, Sendable {
    case transport
    case remoteResponse
    case remoteContent
}
