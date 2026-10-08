// Owns the initial-publication semantic demand and explicit physical resources.
// Target planning and execution remain downstream responsibilities.
import FeedMineDomain

public struct BootstrapPlan: Hashable, Sendable {
    public let demand: AcquisitionDemand
    public let acquisitionResources: AcquisitionPlanningResources

    public init?(contextKey: ContextKey, editorialRevisionID: EditorialRevisionID,
        exhaustedLocalSupply: ExhaustedLocalSupply, acquisitionResources: AcquisitionPlanningResources) {
        guard exhaustedLocalSupply.readyCards == 0,
            let demand = AcquisitionDemand(contextKey: contextKey, editorialRevisionID: editorialRevisionID,
                purpose: .initialPublication, pressure: .initialPublication, localSupply: exhaustedLocalSupply)
        else { return nil }
        self.demand = demand
        self.acquisitionResources = acquisitionResources
    }
}
