import XCTest
import Foundation
import FeedMineUI

/// The first run pre-ticks the device's place, and only when the device states a place it can trust. Each case
/// below is one of the ways a place must stay **unanswered** rather than be guessed from the device.
final class DeviceRegionDraftTests: XCTestCase {
    private let brazil = OnboardingRegion(key: "90_countries/brazil", name: "Brasil")
    private let japan = OnboardingRegion(key: "90_countries/japan", name: "Japão")
    /// The United States, under the shipped catalogue's own spelling (`90_countries/usa`).
    private let usa = OnboardingRegion(key: "90_countries/usa", name: "Estados Unidos")

    /// A Portuguese device in Brazil: the place is offered pre-ticked, in the recipe's own vocabulary, and the
    /// reader still confirms it like any other chip.
    func testAPortugueseDeviceInBrazilPreTicksBrazil() {
        let region = DeviceRegionDraft.region(
            deviceRegion: Locale(identifier: "pt_BR").region?.identifier,
            preferredLanguage: "pt-BR", among: [brazil, japan])
        XCTAssertEqual(region?.key, "90_countries/brazil")
        XCTAssertEqual(region?.preferenceKey, "topic:90_countries/brazil",
            "the draft stores the place where the composer reads every answer")
    }

    /// A language that names no region does not conflict with the device's: `pt` in Brazil still pre-ticks Brazil.
    func testALanguageWithoutARegionDoesNotBlockTheDevicesRegion() {
        XCTAssertEqual(DeviceRegionDraft.region(deviceRegion: "BR", preferredLanguage: "pt",
            among: [brazil])?.key, "90_countries/brazil")
    }

    /// The catalogue's own spelling for the United States is still a place the device can be in.
    func testTheCataloguesOwnSpellingResolves() {
        XCTAssertEqual(DeviceRegionDraft.region(deviceRegion: "US", preferredLanguage: "en-US",
            among: [brazil, usa])?.key, "90_countries/usa")
    }

    /// No region stated, and a code Foundation does not know: nothing is pre-ticked.
    func testADeviceThatStatesNoKnownRegionIsNotGuessed() {
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: nil, preferredLanguage: "pt-BR", among: [brazil]))
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: "  ", preferredLanguage: "pt-BR", among: [brazil]))
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: "ZZ", preferredLanguage: nil, among: [brazil]),
            "a code no region names is not a place")
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: "419", preferredLanguage: "es-419", among: [brazil]),
            "CLDR's numeric region is a real region, but the catalogue names no place for it")
    }

    /// A real region the offered places do not carry: the composer has no chip to pre-tick, so it offers none.
    func testARegionTheOfferedPlacesDoNotCarryIsNotGuessed() {
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: "PT", preferredLanguage: "pt-PT",
            among: [brazil, japan]), "Portugal is a catalogue country, but not among the places offered")
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: "AQ", preferredLanguage: "en-AQ", among: [brazil]),
            "a region with no catalogue node at all")
    }

    /// A device region that disagrees with the language's region is a mixed answer: neither side is pre-ticked,
    /// even though the device's country is one the composer offers.
    func testADeviceRegionThatDiffersFromItsLanguageRegionIsNotGuessed() {
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: "US", preferredLanguage: "pt-BR",
            among: [brazil, usa]))
        XCTAssertNil(DeviceRegionDraft.region(deviceRegion: "BR", preferredLanguage: "en-GB",
            among: [brazil, usa]))
    }
}
