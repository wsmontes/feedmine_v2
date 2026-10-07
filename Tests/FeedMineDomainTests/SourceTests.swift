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
    func testSourceIdentityIsIndependentOfBindingConfiguration() throws {
        let sourceID = SourceID()
        let providerID = ProviderID()
        let provider = Provider(id: providerID, displayName: "Publisher")
        let source = Source(id: sourceID, displayName: "", isEnabled: true)
        let principal = ExternalIdentity(connectorKind: .syndication, namespace: "publisher", value: "Principal A", role: .principal)
        let replacement = ExternalIdentity(connectorKind: .syndication, namespace: "publisher", value: "Principal B", role: .principal)
        let bindingID = SourceBindingID()
        let initial = try XCTUnwrap(SourceBinding(id: bindingID, sourceID: sourceID, externalPrincipal: principal, aliases: [], generation: 17, state: .enabled))
        let changed = try XCTUnwrap(SourceBinding(id: bindingID, sourceID: sourceID, externalPrincipal: replacement, aliases: [], generation: 42, state: .revoked))
        XCTAssertEqual(source.id, initial.sourceID)
        XCTAssertEqual(source.id, changed.sourceID)
        XCTAssertEqual(provider.id, providerID)
        XCTAssertEqual(provider.displayName, "Publisher")
        // SourceID and ProviderID are nominally different; no Source-to-Provider
        // relationship is stored in either independently constructed value.
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
        let binding = try XCTUnwrap(SourceBinding(id: SourceBindingID(), sourceID: SourceID(), externalPrincipal: principal, aliases: [alias], generation: UInt64.max, state: .revoked))
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

    func testBindingConnectorKindIsDerivedFromPrincipal() throws {
        let kind = ConnectorKind(rawValue: "independent-connector")
        let principal = ExternalIdentity(connectorKind: kind, namespace: "", value: "  Identity  ", role: .lookup)
        let binding = try XCTUnwrap(SourceBinding(id: SourceBindingID(), sourceID: SourceID(), externalPrincipal: principal, aliases: [], generation: 0, state: .enabled))
        XCTAssertEqual(binding.connectorKind, principal.connectorKind)
        XCTAssertEqual(binding.externalPrincipal.value, "  Identity  ")
        // Derived convenience state is not encoded as a second independent fact.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any])
        XCTAssertNil(object["connectorKind"])
    }

    func testBindingRejectsAliasFromAnotherConnector() {
        let principal = ExternalIdentity(connectorKind: .syndication, namespace: "principal", value: "A", role: .principal)
        let alias = ExternalIdentity(connectorKind: ConnectorKind(rawValue: "other"), namespace: "alias", value: "B", role: .alias)
        XCTAssertNil(SourceBinding(id: SourceBindingID(), sourceID: SourceID(), externalPrincipal: principal, aliases: [alias], generation: 1, state: .enabled))
    }

    func testBindingAcceptsSameConnectorWithoutOtherValidation() throws {
        let principal = ExternalIdentity(connectorKind: .syndication, namespace: "", value: "", role: .object)
        let alias = ExternalIdentity(connectorKind: .syndication, namespace: "different", value: "  ", role: .version)
        let binding = try XCTUnwrap(SourceBinding(id: SourceBindingID(), sourceID: SourceID(), externalPrincipal: principal, aliases: [alias], generation: 0, state: .revoked))
        XCTAssertEqual(binding.aliases, [alias])
        XCTAssertEqual(binding.connectorKind, .syndication)
    }

    func testBindingDecodingRejectsCrossConnectorAliases() throws {
        let principal = ExternalIdentity(connectorKind: .syndication, namespace: "principal", value: "A", role: .principal)
        let binding = try XCTUnwrap(SourceBinding(id: SourceBindingID(), sourceID: SourceID(), externalPrincipal: principal, aliases: [], generation: 1, state: .enabled))
        let alias = ExternalIdentity(connectorKind: ConnectorKind(rawValue: "other"), namespace: "alias", value: "B", role: .alias)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any])
        object["aliases"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([alias]))
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(SourceBinding.self, from: data))
    }

}
