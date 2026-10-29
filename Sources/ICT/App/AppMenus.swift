import AppKit

/// 顶部菜单栏和程序坞菜单。ICT 在前台时显示：ICT、编辑、字幕、窗口。
/// 编辑菜单不能省：AI 助手和设置里的输入框靠它才能用 ⌘C、⌘V、⌘A。
extension AppDelegate: NSMenuDelegate {
    func setUpMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("关于 ICT"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("设置…", #selector(menuShowSettings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("隐藏 ICT"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L("隐藏其他"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L("全部显示"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("退出 ICT"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu("ICT", appMenu))

        let edit = NSMenu(title: L("编辑"))
        edit.addItem(withTitle: L("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L("重做"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu("编辑", edit))

        // 字幕菜单里的标题和勾选随状态变化，打开时再填（menuNeedsUpdate）。
        let subtitles = NSMenu(title: L("字幕"))
        subtitles.delegate = self
        main.addItem(submenu("字幕", subtitles))

        let window = NSMenu(title: L("窗口"))
        window.addItem(withTitle: L("最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: L("关闭"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu("窗口", window))
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(controller.isRunning || controller.isPaused ? "停止" : "开始", #selector(menuToggleRunning), key: "r"))
        if controller.isRunning || controller.isPaused {
            menu.addItem(item(controller.isPaused ? "继续" : "暂停", #selector(menuTogglePause), key: "p"))
        }
        let show = item(overlay.isVisible ? "收起字幕" : "显示字幕", #selector(menuToggleOverlay), key: "l")
        show.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(show)
        menu.addItem(item("最小化到菜单栏", #selector(menuMinimize)))
        menu.addItem(.separator())
        menu.addItem(checked("置顶字幕", settings.pinned, #selector(menuTogglePin)))
        menu.addItem(checked("锁定字幕", settings.clickThrough, #selector(menuToggleLock)))
        menu.addItem(checked("AI 助手", settings.assistantVisible, #selector(menuToggleAssistant)))
        menu.addItem(.separator())
        menu.addItem(item("字幕记录…", #selector(menuShowHistory), key: "t"))
        menu.addItem(item("历史记录…", #selector(menuShowArchive), key: "y"))
    }

    /// 右键（或按住）程序坞图标时的菜单。
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item(controller.isRunning || controller.isPaused ? "停止" : "开始", #selector(menuToggleRunning)))
        if controller.isRunning || controller.isPaused {
            menu.addItem(item(controller.isPaused ? "继续" : "暂停", #selector(menuTogglePause)))
        }
        if !overlay.isVisible { menu.addItem(item("显示字幕", #selector(menuToggleOverlay))) }
        return menu
    }

    @objc private func menuToggleRunning() {
        if !controller.isRunning, !overlay.isVisible { showSubtitles() }
        controller.toggle()
    }

    @objc private func menuTogglePause() { controller.togglePause() }

    @objc private func menuToggleOverlay() { toggleOverlay() }
    @objc private func menuMinimize() { minimizeToMenuBar() }
    @objc private func menuTogglePin() { togglePin() }

    @objc private func menuToggleLock() {
        settings.clickThrough.toggle()
        overlay.applyClickThrough()
    }

    @objc private func menuToggleAssistant() {
        if !overlay.isVisible { showSubtitles() }
        toggleAssistant()
    }

    @objc private func menuShowSettings() { showSettings() }
    @objc private func menuShowHistory() { showHistory() }
    @objc private func menuShowArchive() { showArchive() }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: L(title), action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func checked(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let item = item(title, action)
        item.state = on ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: L(title), action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
