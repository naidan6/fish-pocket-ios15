# iOS 15.6 回退方案（yg/ios15-backport）

结论先说：**现在这套源码在 iOS 15.6 上装不上**——`app/project.yml:5` 写死 `deploymentTarget: iOS "17.0"`，TestFlight/App Store 包同样按 17.0 打。所以"推之前优化一下"不能是调个开关，是一轮可用性回退。

下面每个数字都是从源码 `grep` 出来的实际调用点数量，不是估计。

## 一、不兼容点清单

| API / 特性 | 引入版本 | 本仓库出现次数 | 15.6 上的替代 |
|---|---|---|---|
| `@Observable` + `@Bindable`（Observation 框架） | **iOS 17** | 28 处 / 26 个文件，`import Observation` 19 个文件 | `ObservableObject` + `@Published` + `@StateObject`/`@ObservedObject`/`@EnvironmentObject` |
| `ContentUnavailableView` | **iOS 17** | 38 处 | `CompatUnavailable`（已写进 `Views/Compat15.swift`） |
| `LabeledContent` | **iOS 16** | 80 处 | `CompatLabeledContent`（已写） |
| `NavigationStack` | **iOS 16** | 61 处 | `NavigationView` + `.stack` 样式（`NavigationStack(path:)` 的值路由要改成 `NavigationLink(destination:)`） |
| `.presentationDetents` | **iOS 16** | 20 处 | `compatDetents()`（已写，15.6 上退全屏） |
| `ShareLink` | **iOS 16** | 19 处 | `CompatShareButton`（已写，走 UIActivityViewController） |
| `.navigationDestination` | **iOS 16** | 14 处 | 删除，改显式 destination |
| `GridRow` | **iOS 16** | 7 处 | `HStack` 手写 |
| `ImageRenderer` | **iOS 16** | 7 处 | `UIGraphicsImageRenderer` 快照 |
| `ActivityKit` / `DynamicIsland`（灵动岛、锁屏实时活动） | **iOS 16.1** | 8 + 8 处 | 15.6 没有，只能整块关闭；对应功能不可用 |
| `NavigationSplitView` | **iOS 16** | 2 处 | 拆成 TabView/自定义分栏 |
| `Chart(` | **iOS 16** | 2 处 | 手绘或去掉 |
| `Table(` | **iOS 16** | 1 处 | `List` + 自定义行 |
| `presentationDragIndicator` / `.toolbarBackground` | **iOS 16** | 3 处 | 去掉 |
| `.symbolEffect` | **iOS 17** | 1 处 | 去掉 |
| `.onChange(of:) { old, new in }` 双参写法 | **iOS 17** | 4 处 | 单参 + 自己存旧值 |

已经有 `#available` 守卫的：`#available(iOS 18…)` 5 处，`#available(iOS 16`、`17` 各 0 处——**说明作者从没打算支持 16 以下**，一行都没守。

第三方依赖：SwiftTerm 1.10、SwiftMath 1.7.3、nodejs-mobile、iOS 版 CPython、libgit2、FFmpeg。这些的下限都 ≤ 15（nodejs-mobile 11+、CPython iOS 13+），不是障碍；障碍全长在 SwiftUI 层。

## 二、realistic 工作量

| 阶段 | 内容 | 机械可做 | 需要编译器 |
|---|---|---|---|
| S1 兼容层 | `Compat15.swift`：空态、LabeledContent、分享、面板高度、搜索空态 | ✅ 已完成 | 只需语法检查 |
| S2 机械替换 | 80 × LabeledContent、38 × ContentUnavailableView、19 × ShareLink、20 × detents、7 × GridRow、1 × symbolEffect | ✅ sed 批量，可逐条 grep 复核 | 是（失败才能确认） |
| S3 结构替换 | 61 × NavigationStack→NavigationView、14 × navigationDestination、2 × NavigationSplitView、7 × ImageRenderer、2 × Chart、1 × Table、8 × Live Activity | ❌ 要理解每个视图的导航语义 | 是（重活） |
| S4 状态模型 | 26 个 `@Observable` 类改成 `ObservableObject`，`@Bindable` 6 处、`@Environment(X.self)` 改 `@EnvironmentObject` | ❌ 每个类都要过一遍，嵌套观察会变 | 是（最容易出回调地狱） |
| S5 真机 | 15.6 设备装 trashed 包，跑通「会话/压缩历史/插件」三条主线 | — | 真机 |

规模判断：S2 约 1000 行 sed 级改动，S3 约 1500–2000 行，S4 约 1500 行且最需要耐心。合计 **3000–4500 行**，不是"优化一下"，是两三天的连续工作 + 反复编译。

## 三、编译怎么验（这台 NAS 没有 Xcode）

新增 `.github/workflows/ios15-compile.yml`：推 `yg/ios15-backport` 就触发，跑 `xcodebuild -sdk iphoneos IPHONEOS_DEPLOYMENT_TARGET=15.6 CODE_SIGNING_ALLOWED=NO`，把 `error:` 和 `is only available` 全打出来。等于把 GitHub 的 macOS runner 当编译器用。

代价：私有仓库 Actions 的 macOS runner 按 **10 倍** 扣分钟，免费额度 2000 分钟/月 → 实际约 **200 分钟**，一次全量编译（含 nodejs-mobile / Python / libgit2 / FFmpeg 缓存未命中）要 30–45 分钟 → **一个月大约 5 次编译**。所以顺序必须是「先在本地把机械活干完，再烧编译」，不能反过来。

## 四、另一条路：不改造整个 App，只做 iOS 15 的壳

`engine/` 全是 JS/TS（nodejs-mobile 加载），**和 iOS 版本无关**；`app/DshIOS/Views/` 才是 iOS 17 绑定。所以可以：
- 保留 `engine/` 原样（宿主、4 个 ios 插件、ios.patch.yml 全不动）；
- 另写一个 iOS 15.6 的 SwiftUI 壳，只实现你真正用的四屏：会话流（含压缩卡片）、输入、审批、插件安装；
- `Models/Timeline.swift` 的折叠逻辑可以照着抄（它本身就是纯数据折叠，没有 iOS 17 API 依赖）。

成本约 2500–3000 行新代码，但**没有 nav/state 迁移的连带风险**，且从第一天就在 15.6 上编译。

## 五、当前分支状态

```
分支  yg/ios15-backport
改动  app/project.yml            deploymentTarget 17.0 → 15.6
新增  app/DshIOS/Views/Compat15.swift           兼容层（201 行，S1 完成）
新增  .github/workflows/ios15-compile.yml       15.6 编译验证
新增  docs/backport/ios15-plan.md               本文件
```

下一步（按顺序）：
1. 推分支 → 触发一次编译，拿到真实错误清单（第一次必然几百条）；
2. 按清单做 S2 机械替换，每批一次编译（预算允许的话 2–3 批）；
3. S3/S4 拆成独立 PR，逐个视图迁移；
4. 15.6 真机装包验证。
