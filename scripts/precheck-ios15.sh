#!/bin/bash
# 15.6 回退的静态体检：把「编译器下一轮才会告诉我」的 API 一次性列出来。
# 用法：bash scripts/precheck-ios15.sh [--strict]
# 退出码：0 = 没有命中；1 = 有命中（--strict 时也一样，方便 CI 里当闸门）。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# 符号|最低 iOS|备注
API_TABLE=$(cat <<'EOF'
onScrollGeometryChange|18.0|滚动几何
scrollPosition|18.0|滚动位置绑定
onScrollPhaseChange|18.0|滚动阶段
containerRelativeFrame|17.0|容器相对尺寸
scrollTargetBehavior|17.0|分页吸附
scrollTargetLayout|17.0|分页布局
contentMargins|17.0|内容边距
symbolEffect|17.0|符号动画
sensoryFeedback|17.0|触感反馈
withObservationTracking|17.0|@Observable 追踪
MagnifyGesture|17.0|缩放手势
onKeyPress|17.0|键盘事件
focusEffectDisabled|17.0|焦点样式
navigationTransition|18.0|导航转场
matchedTransitionSource|18.0|导航转场源
toolbar(removing:|16.4|工具栏移除
toolbarVisibility|18.0|工具栏可见性
defaultScrollAnchor|17.0|滚动锚点
scrollDismissesKeyboard|16.0|键盘收起策略
PasteButton|16.0|粘贴按钮
PhotosPicker|16.0|相册选择
ShareLink|16.0|分享
NavigationStack|16.0|导航栈
NavigationSplitView|16.0|分栏导航
ContentUnavailableView|17.0|空状态
LabeledContent|16.0|标签行
ViewThatFits|16.0|自适应布局
Gauge|16.0|仪表
AnyLayout|16.0|动态布局
Grid|16.0|网格
Chart|16.0|图表
AppTransaction|16.0|StoreKit 2
StoreKit2|16.0|StoreKit 2
contextMenu(menuItems:|16.0|右键菜单带 preview
presentationDetents|16.0|底部弹层高度
presentationDragIndicator|16.0|抓手
presentationCornerRadius|16.4|圆角
presentationBackground|16.4|弹层背景
listRowSeparator|15.0|行分隔
toolbarBackground|16.0|工具栏背景
scrollContentBackground|16.0|滚动背景
scrollBounceBehavior|16.4|滚动弹性
onChange(of:initial:|17.0|变更回调
onGeometryChange|18.0|几何测量
GeometryProxy.bounds(of:|17.0|滚动视图边界
ContinuousClock|16.0|时钟
SuspendingClock|16.0|时钟
Task.sleep(for:|16.0|睡眠
Observation|17.0|@Observable
underline(_:pattern:|16.0|带图案下划线
isToggle|17.0|Toggle 外观
underline()|13.0|基础下划线（允许）
LiveActivityIntent|16.1|实时活动意图
WidgetKit.containerBackground|17.0|容器背景
widgetAccentable|16.0|小组件着色
RegexLiteral|16.0|正则字面量
EOF
)

echo "== 15.6 静态体检（$(date '+%F %T')）"
echo "   仓库：$(pwd) @ $(git rev-parse --short HEAD 2>/dev/null || echo '-')"
echo

hits=0
total=0
while IFS='|' read -r sym version note; do
  [ -z "${sym:-}" ] && continue
  [ "$version" = "13.0" ] && continue          # 允许的基础 API
  case "$sym" in
    RegexLiteral)
      # 正则字面量：#/.../# 与 /.../ 形式
      out=$(grep -rnE --include=*.swift -e '#/[^#]+/#' -e '(^|[^/])/[[:space:]]*\\?\(?' app/DshIOS app/Shared 2>/dev/null | grep -vE 'Compat|//' )
      ;;
    Chart)
      out=$(grep -rn --include=*.swift -e '^import Charts' -e 'Chart(' app/DshIOS app/Shared 2>/dev/null | grep -v Compat)
      ;;
    Observation)
      out=$(grep -rn --include=*.swift -e '@Observable' -e '@ObservationIgnored' -e 'import Observation' app/DshIOS app/Shared app/WatchShared 2>/dev/null | grep -v Compat)
      ;;
    *)
      esc=$(printf '%s' "$sym" | sed 's/[.[\*^$(){}+?|]/\\&/g')
      out=$(grep -rn --include=*.swift -e "$esc" app/DshIOS app/Shared app/WatchShared 2>/dev/null \
              | grep -vE 'Compat|DSH_IOS15_BACKPORT' \
              | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|struct |extension |func |@available|public |private |internal |let |var |case )')
      ;;
  esac
  if [ -n "${out:-}" ]; then
    n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
    printf '  %-34s %-6s %3s 处  %s\n' "$sym" "iOS $version" "$n" "$note"
    if [ "${1:-}" = "--verbose" ]; then printf '%s\n' "$out" | sed 's/^/      /'; fi
    hits=$((hits+1)); total=$((total+n))
  fi
done <<< "$API_TABLE"

echo
echo "合计：$hits 类、$total 处待确认（未命中即已降级干净）"
[ "$hits" -eq 0 ] && exit 0
exit 1
