import AppKit
import SwiftUI

/// 字幕最小化到菜单栏时，菜单栏右侧的小字幕：上面原文、下面译文，各一行，点一下恢复字幕窗口。
/// 平时没有这个图标（2026-10-22 用户要求去掉状态图标），只在最小化期间出现。
@MainActor
final class MenuBarTicker {
    /// 宽度固定：内容变化时菜单栏上别的图标不跟着挪。
    static let width: CGFloat = 360
    private var item: NSStatusItem?
    private let controller: SubtitleController
    private let onClick: () -> Void

    init(controller: SubtitleController, onClick: @escaping () -> Void) {
        self.controller = controller
        self.onClick = onClick
    }

    var isShown: Bool { item != nil }

    func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: Self.width)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.toolTip = L("点击恢复字幕窗口")
        let host = PassthroughHostingView(rootView: MenuBarTickerView(controller: controller))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        self.item = item
    }

    func hide() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    @objc private func clicked() { onClick() }
}

/// 点击交给下面的状态栏按钮处理。
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct MenuBarTickerView: View {
    let controller: SubtitleController

    /// 最近一句已经有译文的字幕（原文和译文成对显示）；还没有时显示正在说的话或状态。
    private var pair: (source: String, translation: String) {
        if let line = controller.lines.last(where: { !$0.translation.isEmpty }) {
            return (line.source, line.translation)
        }
        let live = controller.live.values.first ?? ""
        return (live.isEmpty ? controller.status : live, "")
    }

    var body: some View {
        let pair = pair
        VStack(alignment: .leading, spacing: 0) {
            // 长句只显示结尾，最新的词总在右边看得到。
            Text(pair.source)
                .font(.system(size: 9.5))
                .opacity(0.75)
            Text(pair.translation)
                .font(.system(size: 10.5, weight: .medium))
        }
        .lineLimit(1)
        .truncationMode(.head)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
