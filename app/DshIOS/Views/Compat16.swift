import SwiftUI
import UIKit

// iOS 16.1 补丁层（基线：yyzhp/fish-pocket-ios15 的 yg/ios15-backport 分支）
//
// backport 分支把目标压到了 15.6，替身覆盖了大部分 17+ API，但漏了几处：
// 这些调用点在 15.6 / 16.1 的部署目标下都会直接编译失败（"is only available in iOS 17.0"）。
// 本文件只补缺口，不改 backport 已有的替身。
//
// 放置位置：app/DshIOS/Views/Compat16.swift（xcodegen 扫目录，自动进 target）
//
// 每一条都写清楚「在 16.1 上少掉了什么」，不要假装补齐。

// MARK: - inspector（iOS 17）

extension View {
    /// 替 `.inspector(isPresented:content:)`。
    /// iPhone 没有侧栏容器，用 sheet 呈现同一块内容：宽度、分栏和拖动边缘都没有，
    /// 但工作台本身能用（终端、文件预览、改动列表都在里面）。
    func inspector<V: View>(isPresented: Binding<Bool>,
                            @ViewBuilder content: @escaping () -> V) -> some View {
        modifier(CompatInspector(isPresented: isPresented, pane: content))
    }

    /// `.inspectorColumnWidth(min:ideal:max:)`：16.1 上无对应物。
    func inspectorColumnWidth(min: CGFloat? = nil,
                              ideal: CGFloat? = nil,
                              max: CGFloat? = nil) -> some View {
        self
    }
}

struct CompatInspector<Pane: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let pane: () -> Pane

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            NavigationView { pane() }
                .navigationViewStyle(.stack)
        }
    }
}

// MARK: - defaultScrollAnchor(_:for:)（iOS 17）

/// `.defaultScrollAnchor(_:for:)` 的 placement 参数。
enum CompatScrollAnchorPlacement: Hashable {
    case initialOffset
    case sizeChanges
    case alignment
}

extension View {
    /// 16.1 没有初始锚点机制。调用点用 ScrollViewReader 自己在 onAppear 里滚到底，
    /// 这里只接住参数，避免编译失败。
    func defaultScrollAnchor(_ anchor: UnitPoint?,
                             for placements: CompatScrollAnchorPlacement...) -> some View {
        self
    }
}

// MARK: - scrollClipDisabled / scrollIndicatorsFlash（iOS 17）

extension View {
    /// 16.1 的 ScrollView 不裁剪内容边界以外的东西，默认行为与 `.disabled` 一致。
    func scrollClipDisabled(_ disabled: Bool = true) -> some View { self }

    /// 滚动条闪烁没有开关，忽略。
    func scrollIndicatorsFlash(onAppear: Bool) -> some View { self }

    func scrollIndicatorsFlash<Value: Equatable>(trigger value: Value) -> some View { self }
}

// MARK: - presentationBackgroundInteraction（iOS 16.4）

/// `.presentationBackgroundInteraction(_:)` 的参数类型，16.1 上没有。
enum CompatPresentationBackgroundInteraction: Hashable {
    case automatic
    case enabled
    case disabled
}

extension View {
    /// 16.1 的 sheet 背后一律不可点。`QuestionSheet` 靠这一条让用户能边看边点，
    /// 少了它的后果是：弹层打开时下面的内容点不动，得先关掉弹层。
    func presentationBackgroundInteraction(_ interaction: CompatPresentationBackgroundInteraction) -> some View {
        self
    }

    func presentationBackgroundInteraction<Value: Equatable>(enabledUpThrough value: Value) -> some View {
        self
    }
}

// MARK: - presentationDragIndicator（16.1 有，但 backport 用无参版本）

// backport 的 `compatDragIndicator()` 已经处理，这里不再重复定义。
