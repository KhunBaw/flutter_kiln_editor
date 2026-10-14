import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Editor needs room for three panels; start at 1440x900 and never below 1100x700.
    self.setContentSize(NSSize(width: 1440, height: 900))
    self.contentMinSize = NSSize(width: 1100, height: 700)
    self.center()
    self.backgroundColor = NSColor(red: 0x0F / 255, green: 0x11 / 255, blue: 0x0E / 255, alpha: 1)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
