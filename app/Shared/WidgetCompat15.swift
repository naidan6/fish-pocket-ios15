import SwiftUI
import WidgetKit

// yg/ios15-backport：小组件用到的 iOS 16/17 API 的降级层。
// Widget 扩展的部署目标是 15.6，但 WidgetKit 本身 14 就可用——缺的只是
// 锁屏家族（16）和 containerBackground（17）。这里按系统版本分叉，不砍功能。

extension View {
    /// iOS 17 的 `containerBackground(for: .widget)`；16 及以下退成普通背景。
    @ViewBuilder
    func compatWidgetBackground<S: ShapeStyle>(_ style: S) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(style, for: .widget)
        } else {
            self.background(style)
        }
    }

    /// 同上，背景是视图而不是 ShapeStyle 的那几个（锁屏家族用 Color.clear）。
    @ViewBuilder
    func compatWidgetBackground<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { content() }
        } else {
            self.background(content())
        }
    }

    /// iOS 16 的 `widgetAccentable()`（锁屏单色渲染）；15 上是空操作。
    @ViewBuilder
    func compatWidgetAccentable() -> some View {
        if #available(iOS 16.0, *) {
            self.widgetAccentable()
        } else {
            self
        }
    }
}

@available(iOS 16.0, *)
private let sessionsAccessoryFamilies: [WidgetFamily] = [
    .accessoryCircular, .accessoryRectangular, .accessoryInline,
]

/// 会话状态小组件：桌面三档永远支持，锁屏三档 16 起。
func sessionsWidgetFamilies() -> [WidgetFamily] {
    var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    if #available(iOS 16.0, *) {
        families += sessionsAccessoryFamilies
    }
    return families
}

/// 新对话小组件：桌面两档 + 锁屏圆形（16 起）。
func newConversationWidgetFamilies() -> [WidgetFamily] {
    var families: [WidgetFamily] = [.systemSmall, .systemMedium]
    if #available(iOS 16.0, *) {
        families.append(.accessoryCircular)
    }
    return families
}
