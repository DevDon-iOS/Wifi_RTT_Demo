//
//  IndoorCoordinateTests.swift
//  WifiRTTDemoTests
//
//  Created by 이돈혁
//

import Foundation
import simd
import Testing
@testable import WifiRTTDemo

struct IndoorCoordinateTests {
    private func record(actual: IndoorCoordinate? = nil, arkit: IndoorCoordinate? = nil,
                        rtt: IndoorCoordinate = .origin) -> RTTEvaluation {
        RTTEvaluation(id: UUID(), point: "A", frame: "room", measuredAt: .now,
                      actual: actual, arkit: arkit, arkitCapturedAt: arkit == nil ? nil : .now, rtt: rtt)
    }

    @Test("실제 원점값은 ARKit보다 우선한다")
    func actualAlwaysWins() {
        let value = record(actual: .origin, arkit: .init(x: 50, y: 0, z: 0),
                           rtt: .init(x: 3, y: 4, z: 0))
        #expect(value.source == .actual)
        #expect(value.error == 5)
        #expect(value.arkitError == 50)
    }

    @Test("실제값이 없으면 ARKit 사용, 둘 다 없으면 비교 불가")
    func fallbackAndMissingReference() {
        let value = record(arkit: .init(x: 0, y: 0, z: 2))
        #expect(value.source == .arkit)
        #expect(value.error == 2)
        #expect(record().error == nil)
        #expect(record().source == nil)
    }

    @Test("기준 출처별 통계와 허용 오차 경계를 계산한다")
    func groupedStatistics() {
        let records = [
            record(actual: .origin, rtt: .init(x: 3, y: 0, z: 0)),
            record(actual: .origin, rtt: .init(x: 4, y: 0, z: 0)),
            record(arkit: .origin, rtt: .init(x: 100, y: 0, z: 0)), record()
        ]
        let stats = EvaluationStatistics(records: records, source: .actual, tolerance: 3)
        #expect(stats.count == 2)
        #expect(stats.meanError == 3.5)
        #expect(stats.rmse == sqrt(12.5))
        #expect(stats.withinTolerance == 0.5)
        #expect(EvaluationStatistics(records: [], source: .actual, tolerance: 1).withinTolerance == nil)
    }

    @Test("잘못된 좌표와 중복 및 미지원 파일 버전을 거부한다")
    func validatesArchive() throws {
        #expect(throws: EvaluationError.self) {
            try record(actual: .init(x: .nan, y: 0, z: 0)).validate()
        }
        let value = record(actual: .origin)
        let data = try EvaluationArchive(version: 1, records: [value]).encoded()
        let decoded = try EvaluationArchive.decode(data)
        #expect(decoded.records.first?.actual == .origin)
        #expect(throws: EvaluationError.self) {
            try EvaluationArchive.decode(EvaluationArchive(version: 2, records: [value]).encoded())
        }
        #expect(throws: EvaluationError.self) {
            try EvaluationArchive.decode(EvaluationArchive(version: 1, records: [value, value]).encoded())
        }
    }

    @MainActor @Test("기록은 재로드 후 유지되며 중복 추가는 원본을 보존한다")
    func persistsAtomically() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = EvaluationStore(url: url)
        let value = record(actual: .origin)
        try store.append([value])
        #expect(EvaluationStore(url: url).records.count == 1)
        #expect(throws: EvaluationError.self) { try store.append([value]) }
        #expect(store.records.count == 1)
        #expect(EvaluationStore(url: url).records.count == 1)
    }

    @MainActor @Test("실제값을 나중에 입력하면 동일 기록의 기준과 통계가 바뀐다")
    func upgradesReference() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = EvaluationStore(url: url)
        let value = record(arkit: .init(x: 10, y: 0, z: 0))
        try store.append([value])
        let updated = RTTEvaluation(id: value.id, point: value.point, frame: value.frame,
                                    measuredAt: value.measuredAt, actual: .origin,
                                    arkit: value.arkit, arkitCapturedAt: value.arkitCapturedAt, rtt: value.rtt)
        try store.update(updated)
        let restored = EvaluationStore(url: url)
        #expect(restored.records.count == 1)
        #expect(restored.records.first?.source == .actual)
        #expect(restored.records.first?.error == 0)
        #expect(EvaluationStatistics(records: restored.records, source: .arkit, tolerance: 1).count == 0)
    }
    @MainActor @Test("손상된 원본은 새 기록으로 덮어쓰지 않는다")
    func protectsCorruptArchive() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("invalid archive".utf8)
        try original.write(to: url)
        let store = EvaluationStore(url: url)
        #expect(store.loadError != nil)
        #expect(throws: EvaluationError.self) { try store.append([record(actual: .origin)]) }
        #expect(try Data(contentsOf: url) == original)
    }

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
