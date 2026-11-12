import SwiftUI
import UIKit

// iOS 15.6 回退兼容层（yg/ios15-backport 分支）。
//
// 设计约束：
//  1. 只新增类型/修饰符，绝不重定义 SDK 同名类型（`ContentUnavailableView`、`LabeledContent`
//     这些名字在 iOS 17 SDK 里已存在，重定义会产生歧义或重复声明）。
//  2. 调用点逐个替换成 `Compat*` 名字，机械可查；这样 iOS 16/17 上走原生实现，
//     15.6 上走这里的降级实现，两边行为都能解释。
//  3. 每个 shim 都写清楚「在 iOS 15.6 上少掉了什么」，不要假装补齐。
//
// 完整清单与工作量见 docs/backport/ios15-plan.md。

// MARK: - 面板高度（presentationDetents 是 iOS 16）

enum CompatDetent {
    case medium
    case large
    case height(CGFloat)

    @available(iOS 16.0, *)
    var system: PresentationDetent {
        switch self {
        case .medium: return .medium
        case .large: return .large
        case .height(let h): return .height(h)
        }
    }
}

extension View {
    /// iOS 16 有 presentationDetents；15.6 上退回系统默认高度（全屏 sheet）。
    @ViewBuilder
    func compatDetents(_ detents: [CompatDetent]) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents(Set(detents.map { $0.system }))
        } else {
            self
        }
    }

    /// 面板可拖动关闭：iOS 15 上 sheet 本来就能下滑关闭，这里只是占位。
    @ViewBuilder
    func compatDragIndicator() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

// MARK: - 空态视图（ContentUnavailableView 是 iOS 17）

struct CompatUnavailable<Label: View, Description: View, Actions: View>: View {
    private let label: Label
    private let description: Description
    private let actions: Actions

    init(@ViewBuilder label: () -> Label,
         @ViewBuilder description: () -> Description,
         @ViewBuilder actions: () -> Actions) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label
            description
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

extension CompatUnavailable where Description == EmptyView, Actions == EmptyView {
    /// `ContentUnavailableView("标题", systemImage: "icon")` 的等价物。
    init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.init(label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text(titleKey).font(.headline)
            }
        }, description: { EmptyView() }, actions: { EmptyView() })
    }

    init(_ title: String, systemImage: String) {
        self.init(label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
            }
        }, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension CompatUnavailable where Label == CompatSearchLabel, Description == Text, Actions == EmptyView {
    /// `ContentUnavailableView.search` 的等价物。
    static var search: CompatUnavailable<CompatSearchLabel, Text, EmptyView> {
        CompatUnavailable<CompatSearchLabel, Text, EmptyView>(
            label: { CompatSearchLabel() },
            description: { Text("没找到匹配的内容") },
            actions: { EmptyView() })
    }

    /// `ContentUnavailableView.search(text:)`：搜的是哪一串也写出来。
    static func search(text: String) -> CompatUnavailable<CompatSearchLabel, Text, EmptyView> {
        CompatUnavailable<CompatSearchLabel, Text, EmptyView>(
            label: { CompatSearchLabel() },
            description: { Text("没有与“\(text)”匹配的内容") },
            actions: { EmptyView() })
    }
}

struct CompatSearchLabel: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有结果").font(.headline)
        }
    }
}

// MARK: - 分享（ShareLink 是 iOS 16）

/// ShareLink 的 15.6 等价物：点一下弹 UIActivityViewController。
/// 少了 ShareLink 的 Transferable 预览画质与进度（`preview:`），其余一致。
struct CompatShareButton<Content: View>: View {
    private let items: [Any]
    private let content: Content
    @State private var presented = false

    init(_ items: [Any], @ViewBuilder label: () -> Content) {
        self.items = items
        self.content = label()
    }

    var body: some View {
        Button { presented = true } label: { content }
            .background(ActivityPresenter(items: items, presented: $presented))
    }
}

private struct ActivityPresenter: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var presented: Bool

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard presented, host.presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { presented = false }
        }
        host.present(sheet, animated: true)
    }
}

// MARK: - 卡片列表（LabeledContent 是 iOS 16）

/// LabeledContent 的 15.6 等价物，只覆盖本仓库出现的两种形态：
/// `CompatLabeledContent("标题", value: 值)` 与 `CompatLabeledContent("标题") { 内容 }`。
struct CompatLabeledContent<Content: View>: View {
    private let title: Text
    private let content: Content

    init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(titleKey)
        self.content = content()
    }

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title.foregroundStyle(.secondary)
            Spacer(minLength: 12)
            content.multilineTextAlignment(.trailing)
        }
    }
}

extension CompatLabeledContent where Content == Text {
    init(_ titleKey: LocalizedStringKey, value: String) {
        self.init(titleKey) { Text(value) }
    }

    init(_ title: String, value: String) {
        self.init(title) { Text(value) }
    }
}

// MARK: - 补充：调用点实际用到的重载

extension CompatUnavailable where Description == EmptyView {
    /// `ContentUnavailableView { Label } actions: { … }`：有按钮、没有说明。
    init(@ViewBuilder label: () -> Label, @ViewBuilder actions: () -> Actions) {
        self.init(label: label, description: { EmptyView() }, actions: actions)
    }
}

extension CompatUnavailable where Actions == EmptyView {
    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }
}

extension CompatUnavailable where Description == EmptyView, Actions == EmptyView {
    init(@ViewBuilder label: () -> Label) {
        self.init(label: label, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension CompatUnavailable where Description == Text, Actions == EmptyView {
    init(_ titleKey: LocalizedStringKey, systemImage: String, description: Text) {
        self.init(label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text(titleKey).font(.headline)
            }
        }, description: { description }, actions: { EmptyView() })
    }
}

extension CompatLabeledContent where Content == Text {
    init(_ titleKey: LocalizedStringKey, value: String?) {
        self.init(titleKey) { Text(value ?? "—") }
    }

    init(_ title: String, value: String?) {
        self.init(title) { Text(value ?? "—") }
    }

    init<V>(_ titleKey: LocalizedStringKey, value: V) where V: CustomStringConvertible {
        self.init(titleKey) { Text(value.description) }
    }
}

// MARK: - StoreKit 的 requestReview（iOS 16）降级

extension View {
    /// 15 上没有 `\@Environment(\.requestReview)`；退成直接打开 App Store 的评价页。
    func compatRequestReview(appID: String) {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - onChange(of:initial:_:)（iOS 17）

extension View {
    /// iOS 17 的 `onChange(of:initial:_:)`：15 上用 `onChange(of:perform:)` + 首次 `onAppear` 复现。
    func compatChange<V: Equatable>(of value: V, initial: Bool = false,
                                    _ action: @escaping (V) -> Void) -> some View {
        self.onChange(of: value, perform: action)
            .onAppear { if initial { action(value) } }
    }
}

// MARK: - 正则字面量（iOS 16）的替代

enum CompatRegex {
    /// 单次匹配：返回（整体范围，第一个捕获组）
    static func firstMatch(_ pattern: String, in text: String,
                           caseInsensitive: Bool = false) -> (range: Range<String.Index>, group: String?)? {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              let full = Range(m.range, in: text) else { return nil }
        var group: String?
        if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound, let r = Range(m.range(at: 1), in: text) {
            group = String(text[r])
        }
        return (full, group)
    }

    static func replacing(_ pattern: String, in text: String, with template: String = "",
                          caseInsensitive: Bool = false) -> String {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return text }
        let ns = text as NSString
        return re.stringByReplacingMatches(in: text, options: [],
                                          range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}
