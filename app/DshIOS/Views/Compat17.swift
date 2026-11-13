import SwiftUI

// iOS 17 的 phaseAnimator 在 16.1 上没有：退成「只渲染第一个相位」的静帧，
// 触发值仍然接住，动画效果没有。视觉上少一点跳动，功能不受影响。

extension View {
    func compatPhaseAnimator<Trigger: Equatable, Phase>(
        _ phases: [Phase],
        trigger: Trigger,
        @ViewBuilder content: @escaping (Self, Phase) -> some View,
        animation: @escaping (Phase) -> Animation
    ) -> some View {
        content(self, phases[0])
    }
}
