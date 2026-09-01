import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static let wakePrimaryNotification =
    Notification.Name("com.aaalice.nai-launcher.wake-primary")
  private static var primaryInstanceLock: Int32 = -2
  private static let updateRestartEnvironment = "NAI_LAUNCHER_UPDATE_RESTART"
  private static let updateLockWaitSeconds: TimeInterval = 12

  static func acquirePrimaryInstanceLock() -> Bool {
    if primaryInstanceLock >= 0 { return true }
    if primaryInstanceLock == -1 { return false }
    let identifier = Bundle.main.bundleIdentifier ?? "com.aaalice.nai-launcher"
    let lockPath = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("\(identifier)-\(getuid()).lock")
    let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      primaryInstanceLock = -1
      return false
    }

    let updatePendingPath = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("nai_launcher_updates/pending_update.json")
    let isUpdateRestart =
      ProcessInfo.processInfo.environment[updateRestartEnvironment] == "1" ||
      FileManager.default.fileExists(atPath: updatePendingPath)
    let deadline = Date().addingTimeInterval(updateLockWaitSeconds)

    repeat {
      if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
        let descriptorFlags = fcntl(descriptor, F_GETFD)
        guard descriptorFlags >= 0,
              fcntl(descriptor, F_SETFD, descriptorFlags | FD_CLOEXEC) == 0 else {
          flock(descriptor, LOCK_UN)
          close(descriptor)
          primaryInstanceLock = -1
          return false
        }
        primaryInstanceLock = descriptor
        return true
      }
      if !isUpdateRestart || Date() >= deadline { break }
      usleep(250_000)
    } while true

    close(descriptor)
    primaryInstanceLock = -1
    return false
  }

  static func notifyExistingPrimary() {
    DistributedNotificationCenter.default().post(
      name: wakePrimaryNotification,
      object: nil
    )
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    if !Self.acquirePrimaryInstanceLock() {
      Self.notifyExistingPrimary()
      DispatchQueue.main.async { NSApp.terminate(self) }
      return
    }
    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(wakePrimaryInstance),
      name: Self.wakePrimaryNotification,
      object: nil
    )
    super.applicationWillFinishLaunching(notification)
  }

  @objc private func wakePrimaryInstance() {
    for window in NSApp.windows {
      window.makeKeyAndOrderFront(self)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  // 窗口隐藏到托盘时不自动退出 app（配合 window_manager 的 setPreventClose + hide）
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // 点 Dock 图标时，若当前没有可见窗口，显示并激活已有窗口（从托盘/隐藏状态恢复）
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    DistributedNotificationCenter.default().removeObserver(self)
    if Self.primaryInstanceLock >= 0 {
      flock(Self.primaryInstanceLock, LOCK_UN)
      close(Self.primaryInstanceLock)
      Self.primaryInstanceLock = -2
    }
    super.applicationWillTerminate(notification)
  }
}
