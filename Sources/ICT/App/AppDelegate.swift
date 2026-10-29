import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings = AppSettings.shared
    lazy var controller = SubtitleController(settings: settings)
    var overlay: OverlayWindowController!
    private var assistantWindow: AssistantWindowController!
    private var settingsWindow: NSWindow?
    /// 这次打开设置前的值；关窗口时有改动就问用户完成还是取消。
    private var settingsSnapshot: AppSettings.Snapshot?
    private var historyWindow: NSWindow?
    private var modelServicesWindow: NSWindow?
    private var archiveWindow: NSWindow?
    private lazy var archiveModel = ArchiveModel(settings: settings)
    private let modelServicesState = ModelServicesState()
    private let settingsState = SettingsViewState()
    /// 已经自动弹过下载窗口的语言组合：用户取消后，这次运行里不再反复弹。
    private var promptedLanguagePairs: Set<String> = []
    /// 普通 App：程序坞里有图标，点它把收起的字幕叫回来；顶部有标准菜单（`AppMenus.swift`）。
    /// 平时没有菜单栏右侧的状态图标（2026-10-22 用户要求去掉）；只在最小化到菜单栏时出现（`MenuBarTicker`）。
    /// ⌃⌥L 收起/显示字幕。
    private var showHotKey: GlobalHotKey?
    private lazy var ticker = MenuBarTicker(controller: controller, settings: settings) { [weak self] in self?.showSubtitles() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = settings.appearance.nsAppearance
        setUpMainMenu()
        BackgroundCursor.enable()
        // 提前读好终端里的登录环境变量，第一次翻译时不用等。
        DispatchQueue.global(qos: .utility).async { _ = ClaudeCLI.shellEnvironment() }
        overlay = OverlayWindowController(controller: controller, settings: settings, actions: OverlayActions(
            toggleRunning: { [weak self] in self?.controller.toggle() },
            togglePause: { [weak self] in self?.controller.togglePause() },
            togglePin: { [weak self] in self?.togglePin() },
            minimize: { [weak self] in self?.minimizeToMenuBar() },
            showHistory: { [weak self] in self?.showHistory() },
            showSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) },
            toggleAssistant: { [weak self] in self?.toggleAssistant() },
            settingsChanged: { [weak self] in self?.controller.settingsChanged() },
            manageModels: { [weak self] in self?.showModelServices() }
        ))
        assistantWindow = AssistantWindowController(
            assistant: controller.assistant, settings: settings, overlay: overlay.panel,
            onClose: { [weak self] in self?.toggleAssistant() })
        controller.onAppleLanguagesMissing = { [weak self] in self?.promptAppleLanguageDownload() }
        showSubtitles()
        MainThreadWatchdog.shared.start()

        // ⌃⌥L：显示/收起字幕。
        showHotKey = GlobalHotKey(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey) { [weak self] in
            self?.toggleOverlay()
        }
        if ProcessInfo.processInfo.environment["ICT_AUTOSTART"] == "1" {
            controller.toggle()
        }
    }

    /// 应用已经在运行时再次打开它（Spotlight、Finder 双击）：把字幕叫出来。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSubtitles()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appLog.notice("terminate")
        controller.shutdown()
    }

    // MARK: - 动作

    func toggleOverlay() {
        overlay.isVisible ? hideSubtitles() : showSubtitles()
    }

    /// 收起字幕窗口，在菜单栏上用两行小字继续显示最新的原文和译文。
    func minimizeToMenuBar() {
        hideSubtitles()
        ticker.show()
    }

    /// 字幕和（打开着的）AI 助手一起显示 / 收起。
    func showSubtitles() {
        ticker.hide()
        overlay.show()
        if settings.assistantVisible { showAssistant() }
    }

    /// 打开 AI 助手面板；这时才启动它的 Claude 进程（不用就不占资源）。
    private func showAssistant() {
        assistantWindow.show()
        controller.assistant.warmUp()
    }

    private func hideSubtitles() {
        assistantWindow.hide()
        overlay.hide()
    }

    func toggleAssistant() {
        settings.assistantVisible.toggle()
        if settings.assistantVisible, overlay.isVisible {
            showAssistant()
        } else {
            assistantWindow.hide()
        }
    }

    func togglePin() {
        settings.pinned.toggle()
        overlay.applyPin()
    }

    func showArchive() {
        if archiveWindow == nil {
            archiveWindow = makeWindow(title: L("ICT 历史记录"), view: ArchiveView(model: archiveModel))
            archiveWindow?.setContentSize(NSSize(width: 860, height: 600))
        }
        archiveModel.reload()
        present(archiveWindow!)
    }

    /// 设置里的“恢复默认”：字幕大小和位置、AI 助手位置都回到默认。
    private func resetOverlay() {
        settings.resetOverlaySize()
        overlay.resetPosition()
        assistantWindow.resetPosition()
        showSubtitles()
    }

    func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, state: settingsState,
                                    onTranslationSettingsChanged: { [weak self] in self?.controller.settingsChanged() },
                                    onAppearanceChanged: { [weak self] in
                                        self?.overlay.applyClickThrough()
                                        self?.overlay.applyPin()
                                    },
                                    onManageModels: { [weak self] in self?.showModelServices() },
                                    onResetOverlay: { [weak self] in self?.resetOverlay() },
                                    onDone: { [weak self] in self?.finishSettings(keep: true) })
            settingsWindow = makeWindow(title: L("ICT 设置"), view: view)
            settingsWindow?.delegate = self
        }
        if settingsWindow?.isVisible != true { settingsSnapshot = settings.snapshot }
        present(settingsWindow!)
    }

    /// 改动立即生效（边改边看效果）。“完成”保留；“取消”恢复成打开设置前的样子。
    private func finishSettings(keep: Bool) {
        if !keep, let snapshot = settingsSnapshot, snapshot != settings.snapshot {
            settings.restore(snapshot)
            NSApp.appearance = settings.appearance.nsAppearance
            overlay.applyClickThrough()
            overlay.applyPin()
            controller.settingsChanged()
        }
        settingsSnapshot = nil
        settingsWindow?.orderOut(nil)
    }

    /// 直接关设置窗口（红色按钮、⌘W）：有改动时问完成还是取消。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === settingsWindow, let snapshot = settingsSnapshot, snapshot != settings.snapshot else {
            if sender === settingsWindow { settingsSnapshot = nil }
            return true
        }
        let alert = NSAlert()
        alert.messageText = L("保留对设置的更改吗？")
        alert.informativeText = L("选择“取消”会恢复到打开设置前的样子。")
        alert.addButton(withTitle: L("完成"))
        alert.addButton(withTitle: L("取消"))
        alert.beginSheetModal(for: sender) { [weak self] response in
            self?.finishSettings(keep: response == .alertFirstButtonReturn)
        }
        return false
    }

    /// 系统的语言包下载窗口要挂在普通窗口上（字幕面板不能成为 key 窗口），所以借设置窗口弹出。
    private func promptAppleLanguageDownload() {
        guard #available(macOS 15, *) else { return }
        let pair = settings.sourceLanguage + ">" + settings.targetLanguage
        guard promptedLanguagePairs.insert(pair).inserted else { return }
        showSettings()
        settingsState.download.request(source: settings.source, target: settings.target)
    }

    private func showModelServices() {
        if modelServicesWindow == nil {
            let view = ModelServicesView(settings: settings, state: modelServicesState,
                                         onChanged: { [weak self] in self?.controller.settingsChanged() })
            modelServicesWindow = makeWindow(title: L("模型服务"), view: view)
        }
        present(modelServicesWindow!)
    }

    func showHistory() {
        if historyWindow == nil {
            historyWindow = makeWindow(title: L("ICT 字幕记录"), view: HistoryView(
                controller: controller, onShowArchive: { [weak self] in self?.showArchive() }))
            historyWindow?.setContentSize(NSSize(width: 640, height: 560))
        }
        present(historyWindow!)
    }

    private func makeWindow(title: String, view: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

}
