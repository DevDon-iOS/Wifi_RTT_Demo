//
//  ProjectConfigurationTests.swift
//  WifiRTTDemoTests
//
//  Created by 이돈혁
//

import Foundation
import Testing
@testable import WifiRTTDemo

struct ProjectConfigurationTests {
    @Test("앱은 iPhone 전용으로 빌드된다")
    func appTargetsOnlyIPhone() {
        let deviceFamilies = Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int]

        #expect(deviceFamilies == [1])
    }

    @Test("최소 지원 버전은 iOS 18.0이다")
    func minimumDeploymentTargetIsIOS18() {
        let minimumOSVersion = Bundle.main.object(forInfoDictionaryKey: "MinimumOSVersion") as? String

        #expect(minimumOSVersion == "18.0")
    }
}
