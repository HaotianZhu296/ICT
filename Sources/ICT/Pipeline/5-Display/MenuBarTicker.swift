import AppKit
import SwiftUI

/// 字幕最小化到菜单栏时，菜单栏右侧的小字幕：上面是最新识别出的原文，下面是最新的译文，各一行。
/// 单击恢复字幕窗口；按住左右拖动调整宽度（也可以在设置 › 字幕里调）。
/// 平时没有这个图标（2026-10-22 用户要求去掉状态图标），只在最小化期间出现。
@MainActor
final class MenuBarTicker {
    static let widthRange: ClosedRange<Double> = 100...700
    private var item: NSStatusItem?
    private let controller: SubtitleController
    private let settings: AppSettings
    private let onClick: () -> Void

    init(controller: SubtitleController, settings: AppSettings, onClick: @escaping () -> Void) {
        self.controller = controller
        self.settings = settings
        self.onClick = onClick
    }

    func show() {
        guard item == nil else { return }
        // 宽度固定（不随内容变）：菜单栏上别的图标不会跟着挪。
        let item = NSStatusBar.system.statusItem(withLength: settings.menuBarWidth)
        guard let button = item.button else { return }
        let view = TickerHostingView(rootView: MenuBarTickerView(controller: controller))
        view.toolTip = L("单击恢复字幕窗口，左右拖动调整宽度")
        view.onClick = onClick
        view.onResize = { [weak self] width in
            guard let self else { return }
            self.settings.menuBarWidth = min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        }
        view.currentWidth = { [weak self] in self?.settings.menuBarWidth ?? 0 }
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        self.item = item
        followWidth()
    }

    func hide() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    /// 设置里的宽度（拖动或滑块）一变，菜单栏上的长度跟着变。
    private func followWidth() {
        withObservationTracking {
            item?.length = settings.menuBarWidth
        } onChange: {
            Task { @MainActor [weak self] in self?.followWidth() }
        }
    }
}

/// 自己处理鼠标：没怎么移动就当单击，左右拖动就改宽度。
/// 菜单栏的图标靠右排，往左拖是加宽。
private final class TickerHostingView<Content: View>: NSHostingView<Content> {
    var onClick: () -> Void = {}
    var onResize: (Double) -> Void = { _ in }
    var currentWidth: () -> Double = { 0 }
    private var dragStart: (x: CGFloat, width: Double)?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = (NSEvent.mouseLocation.x, currentWidth())
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let dx = NSEvent.mouseLocation.x - start.x
        if abs(dx) > 3 { dragged = true }
        if dragged { onResize(start.width - dx) }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick() }
        dragStart = nil
    }
}

private struct MenuBarTickerView: View {
    let controller: SubtitleController

    /// 上面一行：正在说的话；没有就用最后一句原文。
    private var source: String {
        let live = controller.live.keys.sorted().compactMap { controller.live[$0] }.joined(separator: " ")
        if !live.isEmpty { return live }
        return controller.lines.last?.source ?? controller.status
    }

    /// 下面一行：最新的译文（最后一句还在翻译时，先显示它已经出来的部分，没有就显示上一句的）。
    private var translation: String {
        controller.lines.last(where: { !$0.translation.isEmpty })?.translation ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 长句只显示结尾，最新的词总在右边看得到。
            Text(source)
                .font(.system(size: 9.5))
                .opacity(0.75)
            Text(translation)
                .font(.system(size: 10.5, weight: .medium))
        }
        .lineLimit(1)
        .truncationMode(.head)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
