import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// yg/ios15-backport：PhotosUI 的 SwiftUI 前端（iOS 16）在 15.6 上不存在。
//
// `PhotosPickerItem` / `.photosPicker(...)` / `PhotosPicker(selection:)` 三个名字在这里
// 用同名替身补上，底下全部落到 iOS 14 就有的 `PHPickerViewController`。
// 选中即读取：图片读成 Data，视频读成临时目录里的文件，读取完成才回调，
// 所以上层拿到的 item 一定已经可以立刻用。

/// 替 `PhotosPickerItem`：一个已读好的选中项。
struct PhotosPickerItem: Identifiable, Hashable {
    let id = UUID()
    let data: Data?
    let movieURL: URL?
    let isMovie: Bool

    /// 只有 `Data` 和 `PickedMovie` 两种请求，其余给 nil。
    func loadTransferable<T>(type: T.Type) async throws -> T? {
        if type == Data.self, let data { return data as? T }
        if type == PickedMovie.self, let movieURL { return PickedMovie(url: movieURL) as? T }
        return nil
    }

    /// `.current` 这类编码策略在 15.6 上无对应开关，保留参数只为调用点不改。
    enum EncodingDisambiguationPolicy { case automatic, current, compatible }
}

/// 把 `PHPickerViewController` 包成 sheet。
private struct CompatPHPickerSheet: UIViewControllerRepresentable {
    let filter: PHPickerFilter
    let limit: Int
    let onPick: ([PhotosPickerItem]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = filter
        config.selectionLimit = limit
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: ([PhotosPickerItem]) -> Void
        init(onPick: @escaping ([PhotosPickerItem]) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            let group = DispatchGroup()
            let lock = NSLock()
            var collected: [PhotosPickerItem] = []
            for result in results {
                let provider = result.itemProvider
                let isMovie = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
                group.enter()
                if isMovie {
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                        defer { group.leave() }
                        guard let url else { return }
                        let dest = FileManager.default.temporaryDirectory
                            .appendingPathComponent("pick-\(UUID().uuidString)")
                            .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        let item = PhotosPickerItem(data: nil, movieURL: dest, isMovie: true)
                        lock.lock(); collected.append(item); lock.unlock()
                    }
                } else {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        defer { group.leave() }
                        guard let data else { return }
                        let item = PhotosPickerItem(data: data, movieURL: nil, isMovie: false)
                        lock.lock(); collected.append(item); lock.unlock()
                    }
                }
            }
            group.notify(queue: .main) { self.onPick(collected) }
        }
    }
}

/// 替 `PhotosPicker(selection:matching:)`：按钮 + sheet，选完写回 binding。
struct PhotosPicker<Label: View>: View {
    @Binding var selection: PhotosPickerItem?
    let filter: PHPickerFilter
    @ViewBuilder var label: () -> Label
    @State private var showing = false

    init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilter = .images,
         @ViewBuilder label: @escaping () -> Label) {
        self._selection = selection
        self.filter = filter
        self.label = label
    }

    var body: some View {
        Button { showing = true } label: { label() }
            .sheet(isPresented: $showing) {
                CompatPHPickerSheet(filter: filter, limit: 1) { items in
                    selection = items.first
                }
            }
    }
}

extension View {
    /// 替 `.photosPicker(isPresented:selection:maxSelectionCount:matching:preferredItemEncoding:)`。
    func photosPicker(isPresented: Binding<Bool>, selection: Binding<[PhotosPickerItem]>,
                      maxSelectionCount: Int = 1,
                      matching filter: PHPickerFilter = .images,
                      preferredItemEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .current) -> some View {
        self.sheet(isPresented: isPresented) {
            CompatPHPickerSheet(filter: filter, limit: max(1, maxSelectionCount)) { items in
                selection.wrappedValue = items
            }
        }
    }
}
