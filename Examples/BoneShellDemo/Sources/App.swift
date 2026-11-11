import UIKit
import BoneShellKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            UIView.setAnimationsEnabled(false)
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "BoneShell", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let tabs = BoneTabBarController(tabs: [
            ShellTab(id: "examples", title: "示例", symbol: "square.grid.2x2", root: DemoCatalogController()),
            ShellTab(id: "materials", title: "材质", symbol: "circle.lefthalf.filled", root: MaterialDemoController()),
            ShellTab(id: "about", title: "关于", symbol: "info.circle", root: AboutDemoController())
        ])
        tabs.view.tintColor = DemoStyle.tint
        tabs.tabBar.accessibilityIdentifier = "demo.tabs"
        let window = UIWindow(windowScene: scene)
        window.tintColor = DemoStyle.tint
        window.rootViewController = tabs
        self.window = window
        window.makeKeyAndVisible()
    }
}
