//
// File: SourceTests.swift
// Module: FeedMineDomainTests
//
// Responsibility:
//   Verify source identity, opaque binding values and explicit generation.
//
// Owns:
//   Focused value-model invariant verification for Phase 1A.
//
// Does not own:
//   Mocks, generic test helpers or verification of future modules.
//
// Allowed dependencies:
//   FeedMineDomain, XCTest and Foundation test values/encoding.
//
// Architectural invariants:
//   INV-12, INV-13; canonical facts stay independent of protocol implementation.
//
// Planned public surface:
//   Phase 1A domain tests only; no production API.
//
// Status:
//   Phase 1A canonical domain invariant tests.
//

import Foundation
import XCTest
import FeedMineDomain

final class SourceTests: XCTestCase {
    func testSourceIdentityIsIndependentOfBindingConfiguration() {
        let sourceID = SourceID()
        let providerID = ProviderID()
        let provider = Provider(id: providerID, displayName: "Publisher")
        let source = Source(id: sourceID, displayName: "", providerID: provider.id, isEnabled: true)
        let principal = ExternalIdentity(connectorKind: .syndication, namespace: "publisher", value: "Principal A", role: .principal)
        let replacement = ExternalIdentity(connectorKind: .syndication, namespace: "publisher", value: "Principal B", role: .principal)
        let bindingID = SourceBindingID()
        let initial = SourceBinding(id: bindingID, sourceID: sourceID, connectorKind: .syndication, externalPrincipal: principal, aliases: [], generation: 17, state: .enabled)
        let changed = SourceBinding(id: bindingID, sourceID: sourceID, connectorKind: .syndication, externalPrincipal: replacement, aliases: [], generation: 42, state: .revoked)
        XCTAssertEqual(source.id, initial.sourceID)
        XCTAssertEqual(source.id, changed.sourceID)
        XCTAssertEqual(source.providerID, provider.id)
        XCTAssertEqual(source.displayName, "")
        // Generation is the explicit semantic configuration revision, not a counter service.
        XCTAssertEqual(initial.generation, 17)
        XCTAssertEqual(changed.generation, 42)
        XCTAssertNotEqual(initial.externalPrincipal, changed.externalPrincipal)
    }

    func testBindingCodablePreservesAllFieldsAndOpaqueIdentity() throws {
        let kind = ConnectorKind(rawValue: "custom-connector")
        let principal = ExternalIdentity(connectorKind: kind, namespace: "Case Sensitive", value: "  HTTPS://Example.COM/Identity?Key=A  ", role: .principal)
        let alias = ExternalIdentity(connectorKind: kind, namespace: "other", value: "Alias", role: .alias)
        let binding = SourceBinding(id: SourceBindingID(), sourceID: SourceID(), connectorKind: kind, externalPrincipal: principal, aliases: [alias], generation: UInt64.max, state: .revoked)
        let decoded = try JSONDecoder().decode(SourceBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(decoded, binding)
        XCTAssertEqual(decoded.externalPrincipal.value, principal.value)
        XCTAssertEqual(decoded.externalPrincipal.namespace, "Case Sensitive")
        XCTAssertEqual(decoded.aliases, [alias])
        XCTAssertEqual(decoded.generation, UInt64.max)
        XCTAssertEqual(decoded.state, .revoked)
        XCTAssertEqual(kind.description, "custom-connector")
        XCTAssertEqual(ConnectorKind.syndication.rawValue, "syndication")
    }
}
