// Owns: the cooling window after consecutive operational failures of one target (review H2).
// Does not own: retries, timers or scheduling; it only tells planning which targets to skip now.
//
// v1 lesson IN-8: fetchAll isolated failures but retried every broken feed on every cycle.
// The delay doubles per consecutive failure from a composition-supplied base, up to a ceiling;
// both are operational bounds (INV-04), and one success clears the history.

import Foundation

public struct AcquisitionBackoffPolicy: Hashable, Sendable {
    public let baseSeconds: Double
    public let ceilingSeconds: Double

    public init?(baseSeconds: Double, ceilingSeconds: Double) {
        guard baseSeconds.isFinite, baseSeconds > 0, ceilingSeconds.isFinite, ceilingSeconds >= baseSeconds else { return nil }
        self.baseSeconds = baseSeconds
        self.ceilingSeconds = ceilingSeconds
    }

    public func delay(afterConsecutiveFailures count: Int) -> Double {
        guard count > 0 else { return 0 }
        let exponent = Double(min(count - 1, 62))
        return min(ceilingSeconds, baseSeconds * pow(2, exponent))
    }
}
