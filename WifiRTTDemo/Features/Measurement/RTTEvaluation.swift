//
//  RTTEvaluation.swift
//  WifiRTTDemo
//
//  Created by 이돈혁
//

import Foundation
import Observation

enum ReferenceSource: String, Codable, CaseIterable {
    case actual, arkit

    var title: String { self == .actual ? "실제 측정값 기준" : "ARKit 기준 (실제값 없음)" }
}

struct RTTEvaluation: Codable, Identifiable {
    let id: UUID
    let point: String
    let frame: String
    let measuredAt: Date
    let actual: IndoorCoordinate?
    let arkit: IndoorCoordinate?
    let arkitCapturedAt: Date?
    let rtt: IndoorCoordinate

    var reference: IndoorCoordinate? { actual ?? arkit }
    var source: ReferenceSource? { actual != nil ? .actual : (arkit != nil ? .arkit : nil) }
    var error: Double? { reference.map { rtt.distance(to: $0) } }
    var arkitError: Double? {
        guard let actual, let arkit else { return nil }
        return arkit.distance(to: actual)
    }

    func validate() throws {
        guard !point.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !frame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              point.count <= 200, frame.count <= 200,
              rtt.isValid, actual?.isValid != false, arkit?.isValid != false,
              (arkit == nil) == (arkitCapturedAt == nil),
              measuredAt.timeIntervalSince1970.isFinite,
              arkitCapturedAt?.timeIntervalSince1970.isFinite != false else {
            throw EvaluationError.invalidRecord
        }
    }
}

enum EvaluationError: LocalizedError {
    case invalidRecord, invalidFile, duplicate, storageUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidRecord: "지점·좌표계·날짜와 유효한 미터 단위 좌표를 확인하세요. ARKit 좌표에는 캡처 시각이 필요합니다."
        case .invalidFile: "지원하는 JSON 형식이 아니거나 파일 제한(5 MB / 10,000건)을 초과했습니다."
        case .duplicate: "동일한 ID의 기록이 이미 있습니다. 중복 파일은 추가하지 않습니다."
        case .storageUnavailable: "기존 기록을 읽지 못해 저장을 중단했습니다. 원본 파일을 확인한 뒤 다시 시도하세요."
        }
    }
}

struct EvaluationArchive: Codable {
    let version: Int
    var records: [RTTEvaluation]

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 5_000_000 else { throw EvaluationError.invalidFile }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(Self.self, from: data)
        guard archive.version == 1, archive.records.count <= 10_000 else {
            throw EvaluationError.invalidFile
        }
        guard Set(archive.records.map(\.id)).count == archive.records.count else {
            throw EvaluationError.duplicate
        }
        try archive.records.forEach { try $0.validate() }
        return archive
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

struct EvaluationStatistics {
    let count: Int
    let meanError: Double?
    let rmse: Double?
    let withinTolerance: Double?

    init(records: [RTTEvaluation], source: ReferenceSource, tolerance: Double) {
        let errors = records.filter { $0.source == source }.compactMap(\.error)
        count = errors.count
        guard !errors.isEmpty, tolerance.isFinite, tolerance > 0 else {
            meanError = nil
            rmse = nil
            withinTolerance = nil
            return
        }
        meanError = errors.reduce(0, +) / Double(count)
        rmse = sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(count))
        withinTolerance = Double(errors.filter { $0 <= tolerance }.count) / Double(count)
    }
}

@MainActor @Observable
final class EvaluationStore {
    private(set) var records: [RTTEvaluation] = []
    private(set) var loadError: String?
    private let url: URL

    init(url: URL = URL.documentsDirectory.appending(path: "rtt-evaluations.json")) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                records = try EvaluationArchive.decode(Data(contentsOf: url)).records
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func append(_ incoming: [RTTEvaluation]) throws {
        try persist(records + incoming)
    }

    func update(_ record: RTTEvaluation) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            throw EvaluationError.invalidRecord
        }
        var updated = records
        updated[index] = record
        try persist(updated)
    }

    private func persist(_ updated: [RTTEvaluation]) throws {
        guard loadError == nil else { throw EvaluationError.storageUnavailable }
        let archive = EvaluationArchive(version: 1, records: updated)
        let data = try archive.encoded()
        // Validate the complete transaction before replacing the saved archive.
        _ = try EvaluationArchive.decode(data)
        try data.write(to: url, options: .atomic)
        records = archive.records
    }
}
