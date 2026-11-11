import UIKit

/// One media surface and one coordinate system behind a native container.
@MainActor
final class ShellUnifiedBackgroundHost {
    let view = ShellBackgroundView()
    private weak var container: UIViewController?
    private(set) weak var owner: BoneViewController?
    private var wantsPlayback = false
    private var surfaces: [ObjectIdentifier: Surface] = [:]

    @MainActor private final class Surface {
        weak var view: UIView?
        let color: UIColor?
        let opaque: Bool
        init(_ view: UIView) {
            self.view = view
            color = view.backgroundColor
            opaque = view.isOpaque
        }
        func restore() { view?.backgroundColor = color; view?.isOpaque = opaque }
    }

    init(container: UIViewController) {
        self.container = container
        view.accessibilityIdentifier = "shell.background.unified"
        view.playbackPriority = 30
        view.isUserInteractionEnabled = false
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isHidden = true
    }

    func activate(for page: BoneViewController, configuration: ShellBackgroundConfiguration, playbackActive: Bool) {
        let continuing = view.configuration == configuration && wantsPlayback
        owner = page
        makeTransparent(page.view)
        if let navigation = page.navigationController { makeTransparent(navigation.view) }
        if let container = container { makeTransparent(container.view) }
        layout()
        view.isHidden = false
        view.apply(configuration)
        // A shared surface remains visible throughout a same-background transition.
        // Retain its player/WebView rather than pausing and rebuilding it per page.
        wantsPlayback = playbackActive || continuing
        view.setPlaybackActive(wantsPlayback)
    }

    func layout() {
        guard owner != nil, let container = container, container.isViewLoaded else { return }
        let parent = container.view!
        if view.superview !== parent { parent.insertSubview(view, at: 0) }
        if view.frame != parent.bounds { view.frame = parent.bounds }
        parent.sendSubviewToBack(view)
    }

    func pause() {
        wantsPlayback = false
        view.setPlaybackActive(false)
    }

    func finishDisplaying(_ page: BoneViewController) {
        if owner === page {
            deactivate()
        } else {
            if page.isViewLoaded { restore(page.view) }
            if let navigation = page.navigationController, navigation !== owner?.navigationController,
               navigation !== container, navigation.isViewLoaded { restore(navigation.view) }
        }
    }

    func deactivate() {
        owner = nil
        wantsPlayback = false
        view.stopAndRelease()
        view.isHidden = true
        for surface in surfaces.values { surface.restore() }
        surfaces.removeAll()
    }

    private func makeTransparent(_ surface: UIView) {
        let id = ObjectIdentifier(surface)
        if surfaces[id] == nil { surfaces[id] = Surface(surface) }
        surface.backgroundColor = .clear
        surface.isOpaque = false
    }

    private func restore(_ surface: UIView) {
        surfaces.removeValue(forKey: ObjectIdentifier(surface))?.restore()
    }
}
