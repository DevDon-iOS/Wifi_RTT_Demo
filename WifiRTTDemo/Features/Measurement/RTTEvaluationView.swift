//
//  RTTEvaluationView.swift
//  WifiRTTDemo
//
//  Created by 이돈혁
//

import SwiftUI
import UniformTypeIdentifiers

struct EvaluationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw EvaluationError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct CoordinateInput: Equatable {
    var x = ""
    var y = ""
    var z = ""

    func coordinate() throws -> IndoorCoordinate? {
        let fields = [x, y, z].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if fields.allSatisfy(\.isEmpty) { return nil }
        let numbers = fields.compactMap(Double.init)
        guard numbers.count == 3 else { throw EvaluationError.invalidRecord }
        let value = IndoorCoordinate(x: numbers[0], y: numbers[1], z: numbers[2])
        guard value.isValid else { throw EvaluationError.invalidRecord }
        return value
    }
}

struct RTTEvaluationView: View {
    let model: MeasurementSessionModel
    let store: EvaluationStore
    @Environment(\.dismiss) private var dismiss
    @State private var point = ""
    @State private var editingID: UUID?
    @State private var frame = ""
    @State private var actual = CoordinateInput()
    @State private var rtt = CoordinateInput()
    @State private var snapshot: IndoorCoordinate?
    @State private var capturedAt: Date?
    @State private var measuredAt = Date.now
    @State private var confirmed = false
    @State private var tolerance = "1.0"
    @State private var message: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var document = EvaluationDocument(data: Data())

    private var toleranceValue: Double? {
        guard let value = Double(tolerance), value.isFinite, value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("실제 측정값이 있으면 항상 우선 사용합니다. 없으면 캡처한 ARKit 좌표를 사용합니다. 둘 다 없으면 RTT 기록만 저장하고 통계에서 제외합니다.")
                    Text("Wi-Fi RTT는 외부 기기가 계산한 위치 좌표를 입력하거나 JSON으로 가져옵니다. iPhone 자체 RTT 측정 기능은 제공하지 않습니다.")
                        .foregroundStyle(.secondary)
                }
                if let error = store.loadError {
                    Section("기록 읽기 실패") { Text(error).foregroundStyle(.red) }
                }
                Section("측정 지점") {
                    TextField("지점 이름 (예: A)", text: $point)
                    TextField("공통 좌표계 ID", text: $frame)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(snapshot != nil)
                    DatePicker("RTT 측정 시각", selection: $measuredAt)
                    Text("모든 좌표는 같은 원점·축·단위(m)여야 합니다. ARKit은 Y가 높이이고 X/Z가 수평면입니다. 다른 기기의 센서 위치 차이도 보정하세요.")
                        .font(.footnote)
                }
                Section("실제 측정 좌표 · 최우선") {
                    coordinateFields($actual, name: "실제")
                    Text("실제값이 없으면 세 칸 모두 비우세요. 0은 유효한 실제 측정값입니다.")
                        .font(.footnote)
                }
                Section("ARKit 좌표 · 실제값 없을 때 기준") {
                    Button("현재 ARKit 좌표 캡처") {
                        guard let value = model.evaluationSnapshot() else {
                            message = "정상 추적 중인 최신 ARKit 좌표가 없습니다. 측정 화면에서 추적 상태를 확인하세요."
                            return
                        }
                        snapshot = value.0
                        capturedAt = value.1
                        frame = model.coordinateFrameID
                        confirmed = false
                    }
                    if let snapshot, let capturedAt {
                        Text(coordinateText(snapshot))
                        Text(capturedAt, format: .dateTime.hour().minute().second())
                        Button("ARKit 캡처 제거", role: .destructive) {
                            self.snapshot = nil
                            self.capturedAt = nil
                            confirmed = false
                        }
                    }
                    Text("캡처한 위치에 정지한 상태에서 RTT를 측정하세요. 움직인 뒤 입력할 때는 해당 지점의 값을 사용해야 합니다.")
                        .font(.footnote)
                }
                Section("외부 Wi-Fi RTT 위치 좌표") {
                    coordinateFields($rtt, name: "RTT")
                    Text("AP까지의 거리나 ping 응답 시간이 아닌, RTT 거리들로 계산한 X/Y/Z 위치를 입력하세요.")
                        .font(.footnote)
                    Toggle("동일 지점·좌표계의 측정값임을 확인", isOn: $confirmed)
                    Button(editingID == nil ? "비교 기록 저장" : "기록 수정 저장") { save() }
                        .disabled(!confirmed || store.loadError != nil)
                    if editingID != nil {
                        Button("편집 취소") { clearDraft() }
                    }
                }
                if let message {
                    Section("처리 결과") { Text(message) }
                }
                Section("평가 조건") {
                    TextField("허용 위치 오차 (m)", text: $tolerance)
                        .keyboardType(.numbersAndPunctuation)
                    Text("기본 1m는 편집 가능한 비교 조건입니다. 허용 오차 내 비율은 저장된 비교 표본 중 해당 조건을 만족한 비율입니다.")
                        .font(.footnote)
                }
                if let toleranceValue {
                    ForEach(ReferenceSource.allCases, id: \.rawValue) { source in
                        statisticsSection(source, tolerance: toleranceValue)
                    }
                } else {
                    Section { Text("허용 오차는 0보다 큰 유한한 숫자여야 합니다.") }
                }
                Section("저장 기록 · \(store.records.count)건") {
                    if store.records.isEmpty { Text("저장된 비교 기록이 없습니다.") }
                    ForEach(store.records.reversed()) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.point).font(.headline)
                            Text(record.source?.title ?? "비교 불가 · 기준값 없음")
                            Text("좌표계: \(record.frame)").font(.caption)
                            Text("RTT: \(coordinateText(record.rtt))")
                            if let actual = record.actual { Text("실제: \(coordinateText(actual))") }
                            if let arkit = record.arkit { Text("ARKit: \(coordinateText(arkit))") }
                            if let error = record.error { Text("RTT 위치 오차: \(meters(error))") }
                            if let error = record.arkitError { Text("ARKit 위치 오차: \(meters(error))") }
                            Button("이 기록 편집") {
                                editingID = record.id
                                point = record.point
                                frame = record.frame
                                actual = input(record.actual)
                                rtt = input(record.rtt)
                                snapshot = record.arkit
                                capturedAt = record.arkitCapturedAt
                                measuredAt = record.measuredAt
                                confirmed = false
                                message = "\(record.point) 편집 중입니다. 위 입력 영역에서 값을 수정하세요."
                            }
                        }
                        .font(.subheadline)
                    }
                }
                Section("파일") {
                    Button("JSON 가져오기") { importing = true }
                        .disabled(store.loadError != nil)
                    Button("JSON 내보내기") {
                        do {
                            document = EvaluationDocument(data: try EvaluationArchive(version: 1, records: store.records).encoded())
                            exporting = true
                        } catch { message = error.localizedDescription }
                    }
                    Text("기록은 앱 재실행과 ARKit 원점 재설정 후에도 유지됩니다. JSON 형식은 README를 참고하세요.")
                        .font(.footnote)
                }
            }
            .navigationTitle("RTT 신뢰도 평가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 5_000_000 else { throw EvaluationError.invalidFile }
                    let archive = try EvaluationArchive.decode(Data(contentsOf: url))
                    try store.append(archive.records)
                    message = "\(archive.records.count)건을 가져왔습니다."
                } catch { message = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                          defaultFilename: "rtt-evaluations") { result in
                do {
                    _ = try result.get()
                    message = "내보내기를 완료했습니다."
                } catch { message = error.localizedDescription }
            }
        }
        .onAppear { if frame.isEmpty { frame = model.coordinateFrameID } }
        .onChange(of: point) { confirmed = false }
        .onChange(of: frame) { confirmed = false }
        .onChange(of: actual) { confirmed = false }
        .onChange(of: rtt) { confirmed = false }
        .onChange(of: measuredAt) { confirmed = false }
    }

    private func coordinateFields(_ input: Binding<CoordinateInput>, name: String) -> some View {
        Group {
            TextField("\(name) X (m)", text: input.x)
            TextField("\(name) Y · 높이 (m)", text: input.y)
            TextField("\(name) Z (m)", text: input.z)
        }
        .keyboardType(.numbersAndPunctuation)
        .autocorrectionDisabled()
    }

    private func statisticsSection(_ source: ReferenceSource, tolerance: Double) -> some View {
        let stats = EvaluationStatistics(records: store.records, source: source, tolerance: tolerance)
        return Section(source.title) {
            Text("비교 표본: \(stats.count)건")
            if let mean = stats.meanError, let rmse = stats.rmse, let ratio = stats.withinTolerance {
                Text("평균 위치 오차: \(meters(mean))")
                Text("RMSE: \(meters(rmse))")
                Text("허용 오차 내 비율: \(ratio, format: .percent.precision(.fractionLength(1)))")
            } else { Text("비교 가능한 표본이 없습니다.") }
        }
    }

    private func save() {
        do {
            guard confirmed, let rttCoordinate = try rtt.coordinate() else { throw EvaluationError.invalidRecord }
            let record = RTTEvaluation(id: editingID ?? UUID(), point: point, frame: frame, measuredAt: measuredAt,
                                       actual: try actual.coordinate(), arkit: snapshot,
                                       arkitCapturedAt: capturedAt, rtt: rttCoordinate)
            try record.validate()
            if editingID != nil { try store.update(record) } else { try store.append([record]) }
            message = record.error.map { "저장 완료 · \(record.source?.title ?? "") · RTT 오차 \(meters($0))" }
                ?? "저장 완료 · 기준값이 없어 비교 통계에서 제외됩니다."
            clearDraft()
        } catch { message = error.localizedDescription }
    }

    private func input(_ coordinate: IndoorCoordinate?) -> CoordinateInput {
        guard let coordinate else { return CoordinateInput() }
        return CoordinateInput(x: String(coordinate.x), y: String(coordinate.y), z: String(coordinate.z))
    }

    private func clearDraft() {
        editingID = nil
        rtt = CoordinateInput()
        actual = CoordinateInput()
        snapshot = nil
        capturedAt = nil
        confirmed = false
    }

    private func meters(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(3))) + " m" }
    private func coordinateText(_ value: IndoorCoordinate) -> String {
        "X \(meters(value.x)) / Y \(meters(value.y)) / Z \(meters(value.z))"
    }
}
