import UIKit
import Dispatch

/// M1 fixed-action probe. Attaches one pan recognizer to the home screen window,
/// measures the upward travel from the bottom band and submits exactly one
/// system screenshot request. Screenshot is used on purpose: it is visually
/// distinct from the native App Switcher, so a single device run separates
/// "gate missing", "sensor missing" and "both working".
///
/// The probe stays always-on and is not wired to Settings; it exists only to
/// prove the mechanism before the real feature replaces it.
final class BottomSwipeUp: NSObject, UIGestureRecognizerDelegate {
    static let shared = BottomSwipeUp()

    private var recognizer: UIPanGestureRecognizer?
    private var startPoint: CGPoint = .zero
    private var dispatching = false
    private var started = false

    private override init() { super.init() }

    func start() {
        guard Thread.isMainThread else { return }
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(activate),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        activate()
    }

    /// The home screen window does not exist during the earliest launch phase,
    /// so attachment is retried on every activation until it succeeds.
    @objc private func activate() {
        guard Thread.isMainThread else { return }
        guard recognizer == nil else { return }
        attach()
    }

    /// Called by the gate hook before the system Home gesture begins.
    func suppresses(start: CGPoint, bounds: CGRect) -> Bool {
        guard Thread.isMainThread, recognizer != nil, canListen else { return false }
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let point = CGPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
        let size = bounds.size
        return geometry(for: size).zone(for: point) != .outside
    }

    private var canListen: Bool {
        !UIAccessibility.isVoiceOverRunning &&
            UIApplication.shared.applicationState == .active &&
            LockAction.unlockedManager() != nil
    }

    private func attach() {
        guard let windowType = NSClassFromString("SBHomeScreenWindow") else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.isKind(of: windowType) {
                let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
                pan.maximumNumberOfTouches = 1
                pan.cancelsTouchesInView = false
                pan.delaysTouchesBegan = false
                pan.delaysTouchesEnded = false
                pan.delegate = self
                window.addGestureRecognizer(pan)
                recognizer = pan
                return
            }
        }
    }

    private func geometry(for size: CGSize) -> BottomSwipeGeometry {
        var safeBottom: CGFloat = 0
        if let window = recognizer?.view as? UIWindow {
            safeBottom = window.safeAreaInsets.bottom
        }
        return BottomSwipeGeometry.current(size: size, safeBottom: safeBottom)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard Thread.isMainThread,
              gestureRecognizer === recognizer,
              touch.type == .direct,
              let view = gestureRecognizer.view,
              canListen else { return false }
        let point = touch.location(in: view)
        return geometry(for: view.bounds.size).zone(for: point) != .outside
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard Thread.isMainThread,
              gestureRecognizer === recognizer,
              let view = gestureRecognizer.view,
              canListen else { return false }
        let point = gestureRecognizer.location(in: view)
        return geometry(for: view.bounds.size).zone(for: point) != .outside
    }

    @objc private func handle(_ pan: UIPanGestureRecognizer) {
        guard Thread.isMainThread, let view = pan.view, canListen else { return }
        switch pan.state {
        case .began:
            startPoint = pan.location(in: view)
            dispatching = false
        case .ended:
            guard !dispatching else { return }
            let geometry = self.geometry(for: view.bounds.size)
            // The origin must still be inside the band; distance comes from the
            // recognizer so the pre-recognition slop is included.
            guard geometry.zone(for: startPoint) != .outside else { return }
            let upward = -pan.translation(in: view).y
            guard geometry.tier(forUpward: upward) != .insufficient else { return }
            dispatching = true
            defer { dispatching = false }
            ScreenshotAction.capture()
        default:
            break
        }
    }
}

// A second retained dyld initializer keeps the probe out of the frozen 0.1.13
// startup files. It defers to the main queue exactly like the tap hook.
@_used
@_section("__DATA,__mod_init_func")
private var bottomSwipeInitializer: @convention(c) () -> Void = {
    DispatchQueue.main.async {
        NativeHomeGestureGate.install()
        BottomSwipeUp.shared.start()
    }
}
