import UIKit

@MainActor
public enum ShellBackgroundPlaybackBudget {
    private static var limit = 1
    private static let coordinator = ShellBackgroundPlaybackCoordinator()

    public static var maximumActivePerScene: Int {
        get { limit }
        set { limit = min(3, max(0, newValue)); coordinator.rebalance() }
    }

    /// A nil scene counts running backgrounds across all scenes, including legacy windows.
    public static func activeCount(in scene: UIWindowScene? = nil) -> Int {
        coordinator.activeCount(in: scene)
    }

    static func register(_ view: ShellBackgroundView) { coordinator.register(view) }
    static func rebalance() { coordinator.rebalance() }
}

@MainActor
private final class ShellBackgroundPlaybackCoordinator {
    private final class Entry {
        weak var view: ShellBackgroundView?
        let order: UInt64
        init(_ view: ShellBackgroundView, order: UInt64) { self.view = view; self.order = order }
    }
    private var entries: [Entry] = []
    private var sequence: UInt64 = 0
    private let legacyScene = NSObject()
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var allocating = false
    private var allocationPending = false

    init() {
        let names: [Notification.Name] = [
            UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification,
            UIApplication.didReceiveMemoryWarningNotification,
            UIScene.didActivateNotification, UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification, UIScene.willEnterForegroundNotification,
            UIWindow.didBecomeVisibleNotification, UIWindow.didBecomeHiddenNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            .NSProcessInfoPowerStateDidChange
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                Task { @MainActor in self?.environmentChanged(notification.name) }
            })
        }
    }

    func register(_ view: ShellBackgroundView) {
        entries.removeAll { $0.view == nil }
        guard !entries.contains(where: { $0.view === view }) else { return }
        sequence &+= 1
        entries.append(Entry(view, order: sequence))
    }

    func activeCount(in scene: UIWindowScene?) -> Int {
        entries.removeAll { $0.view == nil }
        return entries.compactMap(\.view).filter {
            $0.isPlaybackRunning && (scene == nil || $0.window?.windowScene === scene)
        }.count
    }

    func rebalance() {
        if allocating { allocationPending = true; return }
        allocating = true
        repeat {
            allocationPending = false
            allocate()
        } while allocationPending
        allocating = false
    }

    private func allocate() {
        entries.removeAll { $0.view == nil }
        let live = entries.compactMap { entry -> (ShellBackgroundView, UInt64)? in
            guard let view = entry.view, view.configuration?.source.isDynamic == true else { return nil }
            return (view, entry.order)
        }
        let candidates = live.filter { $0.0.backgroundPlaybackBlockReason == nil }.sorted {
            if $0.0.playbackPriority != $1.0.playbackPriority { return $0.0.playbackPriority > $1.0.playbackPriority }
            return $0.1 < $1.1
        }
        let limit = ShellBackgroundPlaybackBudget.maximumActivePerScene
        var counts: [ObjectIdentifier: Int] = [:]
        var granted = Set<ObjectIdentifier>()
        for (view, _) in candidates {
            let sceneKey = view.window?.windowScene.map(ObjectIdentifier.init) ?? ObjectIdentifier(legacyScene)
            let count = counts[sceneKey, default: 0]
            if count < limit {
                granted.insert(ObjectIdentifier(view))
                counts[sceneKey] = count + 1
            }
        }
        // Stop losers first: a priority change must never briefly exceed the scene's budget.
        for (view, _) in live where !granted.contains(ObjectIdentifier(view)) {
            let reason = view.backgroundPlaybackBlockReason
                ?? "Playback paused by scene budget (limit \(limit))."
            view.backgroundSetBudgetGranted(false, reason: reason)
        }
        for (view, _) in candidates where granted.contains(ObjectIdentifier(view)) {
            view.backgroundSetBudgetGranted(true, reason: nil)
        }
        // UIKit does not notify descendants when an ancestor's alpha/hidden state changes.
        // One shared 4 Hz visibility check covers that case; it never decodes or renders frames.
        let needsTimer = live.contains { $0.0.backgroundRequestsPlayback && $0.0.window != nil }
        if needsTimer && timer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.rebalance() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !needsTimer {
            timer?.invalidate()
            timer = nil
        }
    }

    private func environmentChanged(_ name: Notification.Name) {
        if name == UIApplication.didReceiveMemoryWarningNotification {
            ShellBackgroundCache.removeAll()
            for entry in entries { entry.view?.backgroundReleaseForMemoryPressure() }
        } else if name == UIApplication.didBecomeActiveNotification || name == UIScene.didActivateNotification {
            for entry in entries { entry.view?.backgroundResumeAfterActivation() }
        }
        rebalance()
    }

    deinit {
        timer?.invalidate()
        for token in observers { NotificationCenter.default.removeObserver(token) }
    }
}
