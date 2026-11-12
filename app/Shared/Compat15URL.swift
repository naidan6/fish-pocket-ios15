import Foundation

// yg/ios15-backport：URL 的 percentEncoded 系列（iOS 16）的降级。
// 15 上这些方法不存在，但对应的属性（host / path / fragment）从 iOS 2 就有，
// 只是不区分「已解码」——对 dsh:// 这种自己生成的链接，两者等价。

extension URL {
    var compatHost: String? {
        if #available(iOS 16.0, *) { return host(percentEncoded: false) }
        return host
    }

    var compatPath: String {
        if #available(iOS 16.0, *) { return path(percentEncoded: false) }
        return path
    }

    func compatFragment() -> String? {
        if #available(iOS 16.0, *) { return fragment(percentEncoded: false) }
        return fragment
    }
}
