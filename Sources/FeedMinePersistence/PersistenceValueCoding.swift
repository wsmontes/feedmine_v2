// File: PersistenceValueCoding.swift
// Module: FeedMinePersistence
// Owns: internal UUID, checked counter, seed bit-pattern and finite Unix date coding.
// Does not own: semantic publication behavior or generic persistence/CRUD.

import Foundation

enum PersistenceValueCodingError: Error, Equatable, Sendable {
    case invalidRepresentation(String)
    case corruption(String)
}

enum PersistenceValueCoding {
    static func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }

    static func uuid(_ value: String, field: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value), self.uuid(uuid) == value else {
            throw PersistenceValueCodingError.corruption(field)
        }
        return uuid
    }

    static func counter(_ value: UInt64, field: String) throws -> Int64 {
        guard let encoded = Int64(exactly: value) else { throw PersistenceValueCodingError.invalidRepresentation(field) }
        return encoded
    }

    static func counter(_ value: Int64, field: String) throws -> UInt64 {
        guard value >= 0 else { throw PersistenceValueCodingError.corruption(field) }
        return UInt64(value)
    }

    static func seed(_ value: UInt64) -> Int64 { Int64(bitPattern: value) }
    static func seed(_ value: Int64) -> UInt64 { UInt64(bitPattern: value) }

    static func date(_ value: Date, field: String) throws -> Double {
        let encoded = value.timeIntervalSince1970
        guard encoded.isFinite else { throw PersistenceValueCodingError.invalidRepresentation(field) }
        return encoded
    }

    static func date(_ value: Double, field: String) throws -> Date {
        guard value.isFinite else { throw PersistenceValueCodingError.corruption(field) }
        let date = Date(timeIntervalSince1970: value)
        guard date.timeIntervalSince1970.isFinite else { throw PersistenceValueCodingError.corruption(field) }
        return date
    }
}
