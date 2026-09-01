//
//  IndoorCoordinateTests.swift
//  WifiRTTDemoTests
//
//  Created by 이돈혁
//

import simd
import Testing
@testable import WifiRTTDemo

struct IndoorCoordinateTests {
    @Test("카메라 변환 행렬의 이동값을 실내 좌표로 변환한다")
    func convertsCameraTranslation() {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(1.25, -0.5, 2.75, 1)

        let coordinate = IndoorCoordinate(cameraTransform: transform)

        #expect(coordinate == IndoorCoordinate(x: 1.25, y: -0.5, z: 2.75))
    }

    @Test("원점으로부터의 3차원 거리를 계산한다")
    func calculatesDistanceFromOrigin() {
        let coordinate = IndoorCoordinate(x: 2, y: 3, z: 6)

        #expect(coordinate.distanceFromOrigin == 7)
    }

    @Test("샘플 순번과 좌표를 보존한다")
    func preservesSampleValues() {
        let coordinate = IndoorCoordinate(x: 0.1, y: 0.2, z: 0.3)
        let sample = MeasurementSample(sequence: 4, coordinate: coordinate)

        #expect(sample.sequence == 4)
        #expect(sample.coordinate == coordinate)
    }
}
