import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // BLEPeripheralPlugin registration — uncomment after adding to Xcode build target
    // BLEPeripheralPlugin.register(with: self.registrar(forPlugin: "BLEPeripheralPlugin")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
