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
        tabs.barPresentation = Self.presentation(from: ProcessInfo.processInfo.arguments)
        tabs.tabBarAccessories = Self.accessories(from: ProcessInfo.processInfo.arguments)
        tabs.view.tintColor = DemoStyle.tint
        tabs.tabBar.accessibilityIdentifier = "demo.tabs"
        let window = UIWindow(windowScene: scene)
        window.tintColor = DemoStyle.tint
        window.rootViewController = tabs
        self.window = window
        window.makeKeyAndVisible()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-open-navbutton-demo"),
           let navigation = tabs.selectedViewController as? BoneNavigationController {
            navigation.pushViewController(NavigationBarDemoController(), animated: false)
        }
        #endif
    }

    /// Test flags select a presentation without spoofing OS capabilities.
    private static func presentation(from arguments: [String]) -> ShellBarPresentation {
        if arguments.contains("-classic-bars") { return .classic }
        if arguments.contains("-capsule-bars") { return .capsule }
        if arguments.contains("-system-bars") { return .system }
        return .automatic
    }

    /// `-tabs-accessory leading|trailing|both|dynamic` opens with the requested accessory.
    private static func accessories(from arguments: [String]) -> [ShellTabBarAccessory] {
        guard let flag = arguments.firstIndex(of: "-tabs-accessory"),
              arguments.indices.contains(flag + 1) else { return [] }
        let mode = arguments[flag + 1]
        if mode == "dynamic" { return [TabBarDemoController.makeAnimatedAccessory { }] }
        var items: [ShellTabBarAccessory] = []
        if mode == "leading" || mode == "both" {
            items.append(ShellTabBarAccessory(id: "demo.accessory.leading",
                                              icon: .systemSymbol("square.and.pencil"),
                                              position: .leading, accessibilityLabel: "新建") { })
        }
        if mode == "trailing" || mode == "both" {
            items.append(ShellTabBarAccessory(id: "demo.accessory.trailing",
                                              icon: .systemSymbol("magnifyingglass"),
                                              position: .trailing, accessibilityLabel: "搜索") { })
        }
        return items
    }
}
