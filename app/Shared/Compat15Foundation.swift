import Foundation
import SwiftUI

// yg/ios15-backport：`LocalizedStringResource`（iOS 16）的替身。
//
// 这个类型在本项目里只当「一条待本地化的文案」的容器用（WhatsNew 的功能条目、
// 原生能力的说明），不参与 Transferable / App Intents 那些 16 才有的管线。
// 所以替身只需要：能接字符串字面量、能被 Text 显示、能取到本地化后的字符串。

struct LocalizedStringResource: Hashable {
    private let key: String

    init(stringLiteral value: String) { key = value }
    init(_ value: String) { key = value }
    init(_ value: String, bundle: Bundle? = nil, comment: String? = nil) { key = value }
    init(stringLiteral value: String, defaultValue: String.LocalizationValue) { key = value }

    /// 本地化后的文案。15 上走 `String(localized:)`（iOS 15 可用）。
    var text: String { String(localized: String.LocalizationValue(key)) }
}

extension LocalizedStringResource: ExpressibleByStringLiteral {}

extension Text {
    init(_ resource: LocalizedStringResource) {
        self.init(LocalizedStringKey(resource.text))
    }
}

extension String {
    init(localized resource: LocalizedStringResource) {
        self = resource.text
    }
}

extension View {
    /// iOS 16 的 `requestReview`（StoreKit）在 15 上没有；这里退成「打开 App Store 评价页」。
    func compatRequestReview() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let url = URL(string: "https://apps.apple.com/app/id\(Bundle.main.bundleIdentifier ?? "")?action=write-review")
        else { return }
        scene.open(url)
    }
}
