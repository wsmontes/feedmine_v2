import XCTest
import FeedMineDomain
import FeedMineAcquisition

final class BootstrapPlanTests: XCTestCase {
    private let context = FeedContext(request: .main).key
    private let revision = EditorialRevisionID()
    private let resources = AcquisitionPlanningResources(targetWorkCapacity: 2, batchCapacityPerNewExecution: 1,
        observationCapacityPerBatch: 3, byteCapacityPerBatch: 1000)!

    private func demand(_ purpose: AcquisitionPurpose, _ pressure: AcquisitionPressure, ready: Int = 0) -> AcquisitionDemand? {
        .init(contextKey: context, editorialRevisionID: revision, purpose: purpose, pressure: pressure,
            localSupply: ExhaustedLocalSupply(readyCards: ready)!)
    }
    func testA1ReaderContinuationOldPairingsRemainValid() {
        XCTAssertNotNil(demand(.readerContinuation, .coverageDeficit(requiredCards: 2), ready: 1))
        XCTAssertNotNil(demand(.readerContinuation, .logicalTailPressure, ready: 8))
        XCTAssertNil(demand(.readerContinuation, .coverageDeficit(requiredCards: 0)))
        XCTAssertNil(demand(.readerContinuation, .coverageDeficit(requiredCards: 1), ready: 1))
    }
    func testA2ReaderContinuationRejectsInitialPressure() {
        XCTAssertNil(demand(.readerContinuation, .initialPublication))
    }
    func testA3InitialPurposeRequiresInitialPressure() {
        XCTAssertNil(demand(.initialPublication, .logicalTailPressure))
        XCTAssertNil(demand(.initialPublication, .coverageDeficit(requiredCards: 2)))
    }
    func testA4InitialPurposeRequiresZeroReady() {
        XCTAssertNil(demand(.initialPublication, .initialPublication, ready: 1))
        XCTAssertNotNil(demand(.initialPublication, .initialPublication))
    }
    func testA5BootstrapPlanExactDemand() throws {
        let supply = ExhaustedLocalSupply(readyCards: 0)!
        let plan = try XCTUnwrap(BootstrapPlan(contextKey: context, editorialRevisionID: revision,
            exhaustedLocalSupply: supply, acquisitionResources: resources))
        XCTAssertEqual(plan.demand.purpose, .initialPublication)
        XCTAssertEqual(plan.demand.pressure, .initialPublication)
        XCTAssertEqual(plan.demand.contextKey, context)
        XCTAssertEqual(plan.demand.editorialRevisionID, revision)
        XCTAssertEqual(plan.demand.localSupply, supply)
        XCTAssertEqual(plan.acquisitionResources, resources)
    }
    func testA6BootstrapPlanRefusesNonzeroReady() {
        XCTAssertNil(BootstrapPlan(contextKey: context, editorialRevisionID: revision,
            exhaustedLocalSupply: ExhaustedLocalSupply(readyCards: 1)!, acquisitionResources: resources))
    }
}
