import UIKit
import BoneShellKit

@MainActor
enum DemoSplitFactory {
    static func make() -> UIViewController {
        let primary = SplitListController(style: .insetGrouped)
        let detail = SplitDetailController()
        let split = BoneSplitViewController(primary: primary, detail: detail)
        primary.onSelect = { [weak detail, weak split] index in
            detail?.selection = index
            split?.show(.secondary)
        }
        let close: () -> Void = { [weak split] in split?.dismiss(animated: true) }
        primary.onClose = close
        detail.onClose = close
        return split
    }
}

@MainActor
private final class SplitListController: UITableViewController {
    var onSelect: ((Int) -> Void)?
    var onClose: (() -> Void)?
    private let names = ["导航与操作", "内容与安全区", "材质与兼容", "状态与窗口"]
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "示例列表"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        tableView.accessibilityIdentifier = "split.list"
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { names.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = names[indexPath.row]
        cell.detailTextLabel?.text = "打开详情并保留编辑内容"
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { onSelect?(indexPath.row) }
}

@MainActor
private final class SplitDetailController: DemoStackController {
    var onClose: (() -> Void)?
    var selection = 0 {
        didSet {
            if isViewLoaded { selectedLabel.text = "当前条目：\(selection + 1)" }
        }
    }
    private let selectedLabel = DemoStyle.label("当前条目：1", style: .headline)
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "详情"
        screen.navigation.leadingActions = [NavigationAction(id: "split.close", title: "关闭", symbol: "xmark", handler: { [weak self] in self?.onClose?() })]
        screen.avoidsKeyboard = true
    }
    override func buildDemo() {
        intro("系统分栏容器", "在宽窗口查看列表与详情，在紧凑窗口使用系统折叠行为。调整尺寸时，保留同一个详情控制器。")
        card([selectedLabel])
        let editor = UITextView()
        editor.text = "在这里编辑，再调整窗口或旋转设备。"
        editor.font = .preferredFont(forTextStyle: .body)
        editor.adjustsFontForContentSizeCategory = true
        editor.accessibilityIdentifier = "split.editor"
        editor.heightAnchor.constraint(equalToConstant: 220).isActive = true
        card([editor])
    }
}
