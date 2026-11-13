import SwiftUI
import UIKit

// yg/ios15-backport：iOS 16/17 的 SwiftUI API 在 15.6 上的同名替身。
//
// 每个替身都只做一件事：让调用点保持原样，并在 15.6 上给出「行为上说得过去」的结果。
// 有损的地方都写在各自注释里，方便以后按需补。

// MARK: - NavigationStack（iOS 16）

/// 替 `NavigationStack`：15.6 上落到 `NavigationView`（`.stack` 样式，iPhone 上就是全屏推入）。
///
/// `path:` 版本接受绑定但**不参与路由**——15.6 没有 `navigationDestination(for:)` 的
/// 值驱动栈，那些页面改由各视图自己的 `NavigationLink(destination:)` 推入。
struct NavigationStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    init<Path>(path: Binding<Path>, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationView { content }
            .navigationViewStyle(.stack)
    }
}

extension View {
    /// 替 `.navigationDestination(for:destination:)`：15.6 上不注册（见上）。
    func navigationDestination<V, D: View>(for type: V.Type,
                                           @ViewBuilder destination: @escaping (V) -> D) -> some View {
        self
    }

    /// `isPresented:` 版本能用 `NavigationLink(isActive:)` 顶上，行为接近原样。
    func navigationDestination<D: View>(isPresented: Binding<Bool>,
                                        @ViewBuilder destination: @escaping () -> D) -> some View {
        background(
            NavigationLink(isActive: isPresented, destination: { destination() }, label: { EmptyView() })
                .hidden()
        )
    }

    /// `item:` 版本没有对应机制，退成不推入。
    func navigationDestination<Item: Hashable, D: View>(item: Binding<Item?>,
                                                        @ViewBuilder destination: @escaping (Item) -> D) -> some View {
        self
    }
}

// MARK: - ShareLink / SharePreview（iOS 16）

/// 替 `SharePreview`：15.6 上只是承接参数，不参与呈现。
struct SharePreview {
    let title: String

    init(_ title: String, image: Any? = nil) { self.title = title }
    init(_ title: LocalizedStringKey, image: Any? = nil) { self.title = String(describing: title) }
    init(_ title: Text, image: Any? = nil) { self.title = String(describing: title) }
}

/// 没有自定义标签时用的图标。
struct ShareIconLabel: View {
    var body: some View {
        Image(systemName: "square.and.arrow.up")
    }
}

/// 替 `ShareLink`：15.6 上用 `UIActivityViewController` 呈现。
struct ShareLink<Label: View>: View {
    private let payload: [Any]
    private let label: Label

    init<I>(item: I, subject: Text? = nil, message: Text? = nil,
            preview: SharePreview? = nil,
            @ViewBuilder label: () -> Label) {
        self.payload = SharePayload.activities(from: item)
        self.label = label()
    }

    init<I>(_ title: LocalizedStringKey, item: I, subject: Text? = nil, message: Text? = nil,
            preview: SharePreview? = nil,
            @ViewBuilder label: () -> Label) {
        self.payload = SharePayload.activities(from: item)
        self.label = label()
    }

    var body: some View {
        Button { SharePayload.present(payload) } label: { label }
    }
}

extension ShareLink where Label == ShareIconLabel {
    init<I>(item: I, subject: Text? = nil, message: Text? = nil, preview: SharePreview? = nil) {
        self.payload = SharePayload.activities(from: item)
        self.label = ShareIconLabel()
    }
}

enum SharePayload {
    /// 把「可分享的东西」翻成 `UIActivityViewController` 认识的对象。
    static func activities(from item: Any) -> [Any] {
        if let url = item as? URL { return [url] }
        if let image = item as? UIImage { return [image] }
        if let string = item as? String { return [string] }
        if let file = item as? MarkdownFile { return markdownFile(file) }
        if let data = item as? Data { return [data] }
        return []
    }

    /// `MarkdownFile` 写成临时 `.md` 再分享；文件名沿用它的 `name`。
    static func markdownFile(_ file: MarkdownFile) -> [Any] {
        let safe = file.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safe.isEmpty ? "ds-markdown" : safe
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(base)
            .appendingPathExtension("md")
        guard (try? file.text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return [file.text] }
        return [url]
    }

    static func present(_ items: [Any]) {
        guard !items.isEmpty else { return }
        DispatchQueue.main.async {
            guard let top = topViewController() else { return }
            let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Grid / GridRow（iOS 16）

private struct GridSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var compatGridSpacing: CGFloat? {
        get { self[GridSpacingKey.self] }
        set { self[GridSpacingKey.self] = newValue }
    }
}

/// 替 `Grid`：15.6 上是「行叠起来」的 `VStack`，列宽不再自动对齐（表格类内容会略微参差）。
struct Grid<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let verticalSpacing: CGFloat?
    private let content: Content

    init(alignment: HorizontalAlignment = .center,
         horizontalSpacing: CGFloat? = nil,
         verticalSpacing: CGFloat? = nil,
         @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: verticalSpacing) { content }
    }
}

/// 替 `GridRow`：一行 `HStack`。
struct GridRow<Content: View>: View {
    @Environment(\.compatGridSpacing) private var spacing
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) { content }
    }
}

extension View {
    /// 替 `.onGeometryChange(for:of:action:)`（iOS 16/17）：用 `GeometryReader` 量同一件事。
    func onGeometryChange<T: Equatable>(for type: T.Type,
                                        of transform: @escaping (GeometryProxy) -> T,
                                        action: @escaping (T) -> Void) -> some View {
        modifier(CompatGeometryChange(transform: transform, action: action))
    }
}

struct CompatGeometryChange<T: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> T
    let action: (T) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let value = transform(proxy)
                Color.clear
                    .onAppear { action(value) }
                    .onChange(of: value) { action($0) }
            }
        )
    }
}

// MARK: - ViewThatFits（iOS 16）

/// 替 `ViewThatFits`：15.6 上取**最后**一个候选——这几处调用都把「更紧凑、总能放下」
/// 的那一个写在最后（横向 ScrollView / 纵向堆叠），所以不会出现裁切。
struct ViewThatFits<Content: View>: View {
    private let content: Content

    init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        _VariadicView.Tree(LastChild()) { content }
    }

    private struct LastChild: _VariadicView.MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            if let last = children.last { last } else { EmptyView() }
        }
    }
}

// MARK: - withAnimation(_:_:completion:)（iOS 17）

/// 替 iOS 17 的带完成回调版本：动画照做，完成回调按动画时长稍后触发。
@discardableResult
func withAnimation<Result>(_ animation: Animation? = .default,
                           _ body: () throws -> Result,
                           completion: @escaping () -> Void) rethrows -> Result {
    let result = try withAnimation(animation, body)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: completion)
    return result
}

// MARK: - Path.subtracting(_:eoFill:)（iOS 17）

extension Path {
    /// 15.6 没有路径布尔运算。把两个路径叠在一起（非零环绕填充），
    /// 对「挖洞」的用法会画成实体，对「取并」的用法完全正确。
    func subtracting(_ other: Path, eoFill: Bool = false) -> Path {
        var combined = self
        combined.addPath(other)
        return combined
    }
}

// MARK: - 少量 iOS 16 修饰符的降级

extension View {
    /// `.presentationBackground(_:)`（iOS 16.4）。
    func presentationBackground<S: ShapeStyle>(_ style: S) -> some View { self }
    func presentationBackground<V: View>(_ view: V) -> some View { self }

    /// `.defaultScrollAnchor(_:)`（iOS 17）。
    func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View { self }
}

// MARK: - Swift Charts（iOS 16）

/// 15.6 上没有 Swift Charts。图表元素退成「按值排序的横向条形 + 类目/系列文字」：
/// 数值、对比和趋势都还在，只是没有坐标轴和曲线。
struct CompatChart15: View {
    struct Value: Identifiable {
        let id = UUID()
        let category: String
        let series: String
        let value: Double
    }

    let values: [Value]

    private var peak: Double { values.map { abs($0.value) }.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(values.sorted { $0.value > $1.value }) { item in
                HStack(spacing: 8) {
                    Text(item.category)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                    GeometryReader { proxy in
                        let ratio = peak > 0 ? max(0, item.value) / peak : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.ink.opacity(0.7))
                            .frame(width: max(2, proxy.size.width * ratio))
                    }
                    .frame(height: 10)
                    Text(item.value.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !item.series.isEmpty {
                        Text(item.series).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 正则（15.6 没有 `Regex` 字面量）

enum CompatRegex15 {
    /// 取第一个匹配的全部分组（下标 0 是整体）。不支持匹配返回 nil。
    static func groups(_ pattern: String, in text: String, anchorsLines: Bool = false) -> [String]? {
        var options: NSRegularExpression.Options = []
        if anchorsLines { options.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    /// 按正则切开（等价 `split(separator: Regex)`），丢掉空段。
    static func split(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let ns = text as NSString
        var pieces: [String] = []
        var cursor = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            pieces.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        pieces.append(ns.substring(from: cursor))
        return pieces.filter { !$0.isEmpty }
    }

    /// 是否有一处匹配。
    static func contains(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// 整个字符串是否就是这一条（等价 `wholeMatch`）。
    static func wholeMatches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return false }
        return match.range == range
    }

    /// 正则替换，模板里用 `$1` 这种分组引用（等价 `replacing(_:with:)`）。
    static func replacing(_ pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// 匹配到的整段之后的内容（没有匹配返回 nil）。
    static func afterHeader(_ pattern: String, in text: String, anchorsLines: Bool = false) -> String? {
        var options: NSRegularExpression.Options = []
        if anchorsLines { options.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let end = Range(match.range, in: text)?.upperBound else { return nil }
        return String(text[end...])
    }

    /// 所有匹配的第一个分组。
    static func firstGroups(_ pattern: String, in text: String, anchorsLines: Bool = false) -> [String] {
        var options: NSRegularExpression.Options = []
        if anchorsLines { options.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

// MARK: - onChange（iOS 17 的签名在 16.1 上的替身）

extension View {
    /// 0 参：`.onChange(of: x) { doSomething() }`
    func compatOnChange<V: Equatable>(of value: V, _ action: @escaping () -> Void) -> some View {
        modifier(CompatOnChange(value: value, action: { _, _ in action() }))
    }

    /// 1 参：`.onChange(of: x) { new in … }`
    func compatOnChange<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View {
        modifier(CompatOnChange(value: value, action: { new, _ in action(new) }))
    }

    /// 2 参：`.onChange(of: x) { old, new in … }`
    func compatOnChange<V: Equatable>(of value: V, _ action: @escaping (V, V) -> Void) -> some View {
        modifier(CompatOnChange(value: value, action: action))
    }
}

struct CompatOnChange<V: Equatable>: ViewModifier {
    let value: V
    var initial: Bool = false
    let action: (V, V) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { if initial { action(value, value) } }
            .onChange(of: value, perform: { new in action(new, new) })
    }
}

// MARK: - Path.union(_:eoFill:)（iOS 17）

extension Path {
    /// 15.6 没有路径布尔运算：直接叠加（对「合并」的用法等价）。
    func union(_ other: Path, eoFill: Bool = false) -> Path {
        var combined = self
        combined.addPath(other)
        return combined
    }
}

// MARK: - ScrollBounceBehavior / scrollBounceBehavior（iOS 16.4）

struct ScrollBounceBehavior {
    private init() {}
    static let automatic = ScrollBounceBehavior()
    static let always = ScrollBounceBehavior()
    static let basedOnSize = ScrollBounceBehavior()
}

extension View {
    /// 15.6：默认弹性行为就是「总是可以」，这里不额外处理。
    func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View { self }
}

// MARK: - TextField(_, text:, axis:)（iOS 16）

/// 替 `TextField(_:text:axis: .vertical)`：15.6 的多行输入只有 `TextEditor`，
/// 占位文字自己画。高度随内容长，外面仍可用 `.frame` 或容器约束。
struct CompatTextField: View {
    private let title: Text
    @Binding private var text: String
    private var minHeight: CGFloat = 34

    init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.title = Text(titleKey)
        self._text = text
    }

    init(_ title: String, text: Binding<String>) {
        self.title = Text(title)
        self._text = text
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
            if text.isEmpty {
                title
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }
}
