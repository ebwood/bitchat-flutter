import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Register native BLE plugin for macOS CoreBluetooth
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let registrar = controller.registrar(forPlugin: "BLEPlugin")
      BLEPlugin.register(with: registrar)
    }
  }
}
