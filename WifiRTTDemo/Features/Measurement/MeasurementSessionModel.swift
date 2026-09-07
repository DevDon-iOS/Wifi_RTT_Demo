//
//  MeasurementSessionModel.swift
//  WifiRTTDemo
//
//  Created by 이돈혁
//

@preconcurrency import ARKit
import AVFoundation
import Dispatch
import Foundation
import Observation

@MainActor
@Observable
final class MeasurementSessionModel: NSObject, @preconcurrency ARSessionDelegate {
    enum State: Equatable, Sendable {
        case permissionRequired
        case requestingPermission
        case ready
        case running
        case limited(String)
        case paused
        case denied
        case unsupported
        case interrupted
        case failed(String)
    }

    let session = ARSession()

    private(set) var state: State
    private(set) var coordinate = IndoorCoordinate.origin
    private(set) var samples: [MeasurementSample] = []
    private(set) var hasCurrentFrame = false
    private(set) var coordinateFrameID = UUID().uuidString
    private var frameReceivedAt: Date?
    private var isActive = true

    func evaluationSnapshot() -> (IndoorCoordinate, Date)? {
        guard isActive, state == .running, let frameReceivedAt,
              Date.now.timeIntervalSince(frameReceivedAt) < 1 else { return nil }
        return (coordinate, frameReceivedAt)
    }

    private var shouldResume = false
    private var lastPublishedTimestamp: TimeInterval = 0
    private var pendingReset = false

    override init() {
        if !ARWorldTrackingConfiguration.isSupported {
            state = .unsupported
        } else {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                state = .ready
            case .notDetermined:
                state = .permissionRequired
            case .denied, .restricted:
                state = .denied
            @unknown default:
                state = .denied
            }
        }

        super.init()
        session.delegateQueue = .main
        session.delegate = self
    }

    var isMeasuring: Bool {
        switch state {
        case .running, .limited, .paused, .interrupted:
            true
        default:
            false
        }
    }

    func start() async {
        guard ARWorldTrackingConfiguration.isSupported else {
            state = .unsupported
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run(resetOrigin: true)
        case .notDetermined:
            state = .requestingPermission
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            granted ? run(resetOrigin: true) : setPermissionDenied()
        case .denied, .restricted:
            setPermissionDenied()
        @unknown default:
            setPermissionDenied()
        }
    }

    func recordSample() {
        guard hasCurrentFrame else { return }

        samples.append(
            MeasurementSample(
                sequence: samples.count + 1,
                coordinate: coordinate
            )
        )
    }

    func resetOrigin() {
        guard isMeasuring else { return }

        coordinate = .origin
        hasCurrentFrame = false
        samples.removeAll()
        run(resetOrigin: true)
    }

    func stop() {
        shouldResume = false
        session.pause()
        coordinate = .origin
        hasCurrentFrame = false
        samples.removeAll()
        refreshReadyState()
    }

    func pauseForBackground() {
        isActive = false
        hasCurrentFrame = false
        guard shouldResume else { return }
        session.pause()
        state = .paused
    }

    func resumeAfterBackground() {
        isActive = true
        guard shouldResume else { return }
        run(resetOrigin: false)
    }

    func refreshAuthorizationState() {
        guard !isMeasuring, ARWorldTrackingConfiguration.isSupported else { return }
        refreshReadyState()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard shouldResume, isActive, state != .interrupted else { return }

        let timestamp = frame.timestamp
        guard timestamp - lastPublishedTimestamp >= 0.1 else { return }
        lastPublishedTimestamp = timestamp

        coordinate = IndoorCoordinate(cameraTransform: frame.camera.transform)
        frameReceivedAt = .now
        hasCurrentFrame = true
        updateTrackingState(frame.camera.trackingState)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard shouldResume else { return }
        hasCurrentFrame = false
        state = .interrupted
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard shouldResume else { return }
        run(resetOrigin: false)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        shouldResume = false
        hasCurrentFrame = false
        session.pause()
        state = .failed(error.localizedDescription)
    }

    private func run(resetOrigin: Bool) {
        if resetOrigin {
            pendingReset = true
            coordinateFrameID = UUID().uuidString
            coordinate = .origin
        }
        hasCurrentFrame = false
        frameReceivedAt = nil
        lastPublishedTimestamp = 0
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity

        let options: ARSession.RunOptions = pendingReset
            ? [.resetTracking, .removeExistingAnchors]
            : []

        shouldResume = true
        state = isActive ? .limited("주변 공간을 천천히 비춰 초기화하세요.") : .paused
        if isActive {
            session.run(configuration, options: options)
            pendingReset = false
        }
    }

    private func setPermissionDenied() {
        shouldResume = false
        state = .denied
    }

    private func refreshReadyState() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .ready
        case .notDetermined:
            state = .permissionRequired
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    private func updateTrackingState(_ trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            state = .running
        case .notAvailable:
            state = .limited("카메라 추적을 사용할 수 없습니다.")
        case let .limited(reason):
            state = .limited(Self.message(for: reason))
        }
    }

    private static func message(for reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing:
            "주변 공간을 천천히 비춰 초기화하세요."
        case .excessiveMotion:
            "iPhone을 조금 더 천천히 움직이세요."
        case .insufficientFeatures:
            "조명이 밝고 특징이 많은 표면을 비추세요."
        case .relocalizing:
            "이전에 측정한 공간을 비춰 위치를 복구하세요."
        @unknown default:
            "추적 품질이 제한되었습니다."
        }
    }
}
