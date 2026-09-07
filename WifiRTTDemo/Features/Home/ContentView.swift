//
//  ContentView.swift
//  WifiRTTDemo
//
//  Created by 이돈혁
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = MeasurementSessionModel()
    @State private var isShowingSamples = false
    @State private var evaluations = EvaluationStore()
    @State private var isShowingEvaluation = false

    var body: some View {
        NavigationStack {
            Group {
                if model.isMeasuring {
                    measurementView
                } else {
                    setupView
                }
            }
            .navigationTitle(model.isMeasuring ? "좌표 측정" : "실내 좌표 측정")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isShowingSamples) {
                samplesView
            }
            .sheet(isPresented: $isShowingEvaluation) {
                RTTEvaluationView(model: model, store: evaluations)
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    model.refreshAuthorizationState()
                    model.resumeAfterBackground()
                case .inactive, .background:
                    model.pauseForBackground()
                @unknown default:
                    break
                }
            }
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: setupIconName)
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(setupTitle)
                        .font(.title2.bold())

                    Text(setupMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if shouldShowMeasurementGuide {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("카메라와 모션 센서로 이동 좌표를 계산합니다.", systemImage: "camera")
                        Label("좌표와 기록은 기기 밖으로 전송하지 않습니다.", systemImage: "lock")
                        Label("밝고 특징이 많은 실내 공간에서 측정하세요.", systemImage: "light.max")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }

                setupAction
                Button("실제값 / RTT 입력 및 비교") { isShowingEvaluation = true }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: 560)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var setupAction: some View {
        switch model.state {
        case .permissionRequired, .ready, .failed:
            Button {
                Task { await model.start() }
            } label: {
                Label("측정 시작", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        case .requestingPermission:
            ProgressView("카메라 권한 확인 중…")
                .frame(minHeight: 44)
        case .denied:
            Button("설정에서 카메라 권한 열기") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
        case .unsupported:
            EmptyView()
        case .running, .limited, .paused, .interrupted:
            EmptyView()
        }
    }

    private var measurementView: some View {
        ZStack {
            ARSessionView(session: model.session)
                .ignoresSafeArea()

            ViewThatFits(in: .vertical) {
                VStack(spacing: 12) {
                    trackingStatusView
                    Spacer(minLength: 16)
                    coordinatePanel
                }
                ScrollView {
                    VStack(spacing: 12) {
                        trackingStatusView
                        coordinatePanel
                    }
                }
            }
            .padding(16)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var trackingStatusView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)

                if let detail = statusDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var coordinatePanel: some View {
        VStack(spacing: 16) {
            Button("실제값 / RTT 입력 및 비교") { isShowingEvaluation = true }
                .buttonStyle(.bordered)
            HStack {
                Text("현재 좌표")
                    .font(.headline)

                Spacer()

                Text("원점 거리 \(model.coordinate.distanceFromOrigin, format: .number.precision(.fractionLength(2))) m")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                coordinateValue(axis: "X", value: model.coordinate.x)
                coordinateValue(axis: "Y", value: model.coordinate.y)
                coordinateValue(axis: "Z", value: model.coordinate.z)
            }

            HStack(spacing: 8) {
                Button {
                    model.recordSample()
                } label: {
                    Label("기록", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasCurrentFrame)

                Button {
                    model.resetOrigin()
                } label: {
                    Label("원점 재설정", systemImage: "scope")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button {
                    isShowingSamples = true
                } label: {
                    Label("기록 \(model.samples.count)개", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.samples.isEmpty)

                Button(role: .destructive) {
                    model.stop()
                } label: {
                    Label("측정 종료", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func coordinateValue(axis: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(axis)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(value, format: .number.precision(.fractionLength(3)))
                .font(.title3.monospacedDigit().bold())
                .minimumScaleFactor(0.7)

            Text("m")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(axis) 좌표")
        .accessibilityValue("\(value.formatted(.number.precision(.fractionLength(3)))) 미터")
    }

    private var samplesView: some View {
        NavigationStack {
            List(model.samples.reversed()) { sample in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("샘플 \(sample.sequence)")
                            .font(.headline)
                        Spacer()
                        Text(sample.recordedAt, format: .dateTime.hour().minute().second())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("X \(sample.coordinate.x, format: .number.precision(.fractionLength(3))) · Y \(sample.coordinate.y, format: .number.precision(.fractionLength(3))) · Z \(sample.coordinate.z, format: .number.precision(.fractionLength(3))) m")
                        .font(.subheadline.monospacedDigit())

                    Text("원점 거리 \(sample.coordinate.distanceFromOrigin, format: .number.precision(.fractionLength(3))) m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("측정 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { isShowingSamples = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var setupIconName: String {
        switch model.state {
        case .denied: "camera.badge.ellipsis"
        case .unsupported: "iphone.slash"
        case .failed: "exclamationmark.triangle"
        default: "camera.viewfinder"
        }
    }

    private var setupTitle: String {
        switch model.state {
        case .denied: "카메라 권한이 필요합니다"
        case .unsupported: "이 기기에서는 측정할 수 없습니다"
        case .failed: "측정을 시작하지 못했습니다"
        default: "iPhone을 실내 좌표계로 사용합니다"
        }
    }

    private var setupMessage: String {
        switch model.state {
        case .denied:
            "설정에서 카메라 접근을 허용한 뒤 다시 측정하세요."
        case .unsupported:
            "ARKit world tracking은 지원되는 실제 iPhone에서 실행해야 합니다."
        case let .failed(message):
            message
        default:
            "시작 위치를 원점(0, 0, 0)으로 정하고 이동 거리를 미터 단위로 확인합니다."
        }
    }

    private var shouldShowMeasurementGuide: Bool {
        switch model.state {
        case .permissionRequired, .ready, .failed:
            true
        default:
            false
        }
    }

    private var statusTitle: String {
        switch model.state {
        case .running: "추적 중"
        case .limited: "추적 품질 제한"
        case .paused: "측정 일시 정지"
        case .interrupted: "측정 중단됨"
        default: "측정 준비 중"
        }
    }

    private var statusDetail: String? {
        switch model.state {
        case let .limited(message): message
        case .paused: "앱으로 돌아오면 측정을 재개합니다."
        case .interrupted: "카메라를 다시 사용할 수 있을 때 재개합니다."
        default: nil
        }
    }

    private var statusIconName: String {
        model.state == .running ? "location.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        model.state == .running ? .green : .orange
    }
}

#Preview("Small iPhone", traits: .fixedLayout(width: 375, height: 667)) {
    ContentView()
}

#Preview("Reference iPhone", traits: .fixedLayout(width: 393, height: 852)) {
    ContentView()
}

#Preview("Large iPhone", traits: .fixedLayout(width: 440, height: 956)) {
    ContentView()
}
