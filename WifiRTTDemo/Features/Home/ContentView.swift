//
//  ContentView.swift
//  WifiRTTDemo
//
//  Created by 이돈혁
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("실내 측정 준비 완료")
                    .font(.title2.bold())

                Text("iPhone에서 실내지도와 좌표 정확도를 검증하기 위한 데모입니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle("WiFi RTT Demo")
        }
    }
}

#Preview {
    ContentView()
}
