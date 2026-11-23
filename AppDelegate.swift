import UIKit
import Network

final class NetMonitor {
    static let shared = NetMonitor()
    private let monitor = NWPathMonitor()
    private(set) var isWiFi = true
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        }
        monitor.start(queue: DispatchQueue(label: "netmonitor"))
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        _ = NetMonitor.shared
        let window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: CameraViewController())
        nav.isNavigationBarHidden = true
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
        UploadQueue.shared.kick()
        return true
    }
}