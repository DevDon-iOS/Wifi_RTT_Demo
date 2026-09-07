//
//  IndoorCoordinate.swift
//  WifiRTTDemo
//
//  Created by 이돈혁
//

import Foundation
import simd

struct IndoorCoordinate: Equatable, Sendable, Codable {
    static let origin = IndoorCoordinate(x: 0, y: 0, z: 0)

    let x: Double
    let y: Double
    let z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(cameraTransform: simd_float4x4) {
        let translation = cameraTransform.columns.3
        self.init(
            x: Double(translation.x),
            y: Double(translation.y),
            z: Double(translation.z)
        )
    }

    var distanceFromOrigin: Double {
        sqrt((x * x) + (y * y) + (z * z))
    }

    var isValid: Bool {
        [x, y, z].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
    }

    func distance(to other: Self) -> Double {
        hypot(hypot(x - other.x, y - other.y), z - other.z)
    }
}

struct MeasurementSample: Identifiable, Equatable, Sendable {
    let id: UUID
    let sequence: Int
    let recordedAt: Date
    let coordinate: IndoorCoordinate

    init(
        id: UUID = UUID(),
        sequence: Int,
        recordedAt: Date = .now,
        coordinate: IndoorCoordinate
    ) {
        self.id = id
        self.sequence = sequence
        self.recordedAt = recordedAt
        self.coordinate = coordinate
    }
}
