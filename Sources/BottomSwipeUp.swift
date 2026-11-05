import UIKit
import Dispatch

/// M1 fixed-action probe. Attaches one pan recognizer to the home screen window
/// and to every icon list view, measures the upward travel from the bottom band
/// and submits exactly one system screenshot request. Screenshot is used on
/// purpose: it is visually distinct from the native App Switcher, so a single
/// device run separates "gate missing", "sensor missing" and "both working".
///
/// The probe stays always-on and is not wired to Settings; it exists only to
/// prove the mechanism before the real feature replaces it.
final class BottomSwipeUp: NSObject, UIGestureRecognizerDelegate {
    static let shared = BottomSwipeUp()

    private var recognizers: [UIPanGestureRecognizer] = []
    private var startPoints: [ObjectIdentifier: CGPoint] = [:]
    private var dispatching = false
    private var started = false
    private var lastFire: CFAbsoluteTime = 0
    private var touches = 0

    private override init() { super.init() }

    /// Escape hatch: writing `BottomSwipeProbeDisabled = true` into
    /// com.tsangbaby.taplock turns the probe off without uninstalling.
    private var disabled: Bool {
        UserDefaults(suiteName: TapLockPreferences.domain)?.bool(forKey: "BottomSwipeProbeDisabled") ?? false
    }

    func start() {
        guard Thread.isMainThread, !disabled else { return }
        guard !started else { return }
        started = true
        ProbeLog.write("start build=v7")
        NotificationCenter.default.addObserver(
            self, selector: #selector(activate),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        activate()
    }

    /// The home screen window does not exist during the earliest launch phase,
    /// so attachment is retried on every activation until it succeeds. The gate
    /// installs here as well: enumerating classes during image loading crashes,
    /// so resolution is deferred until the application is fully active.
    @objc private func activate() {
        guard Thread.isMainThread, !disabled else { return }
        NativeHomeGestureGate.install()
        guard recognizers.isEmpty else { return }
        attach()
    }

    /// Probe-only self report: every gate check that can silently disable the
    /// veto is recorded here, so one device run names the failing stage.
    func probeState(start: CGPoint, bounds: CGRect) -> String {
        let point = CGPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
        let zone = bounds.width > 0 && bounds.height > 0
            ? String(describing: geometry(for: bounds.size).zone(for: point))
            : "nobounds"
        return "sensor=\(recognizers.count) vo=\(UIAccessibility.isVoiceOverRunning)"
            + " active=\(UIApplication.shared.applicationState.rawValue)"
            + " lock=\(LockAction.unlockedManager() != nil) zone=\(zone)"
            + " y=\(Int(start.y)) h=\(Int(bounds.height))"
    }

    /// Called by the gate hook before the system Home gesture begins.
    func suppresses(start: CGPoint, bounds: CGRect) -> Bool {
        guard Thread.isMainThread, !recognizers.isEmpty, canListen else { return false }
        guard bounds.width > 0, bounds.height > 0 else { return false }
        let point = CGPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
        return geometry(for: bounds.size).zone(for: point) != .outside
    }

    private var canListen: Bool {
        !UIAccessibility.isVoiceOverRunning &&
            UIApplication.shared.applicationState == .active &&
            LockAction.unlockedManager() != nil
    }

    private func attach() {
        guard let windowType = NSClassFromString("SBHomeScreenWindow"),
              let listType = NSClassFromString("SBIconListView") else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.isKind(of: windowType) {
                addPan(to: window)
                var pending: [UIView] = window.subviews
                while let view = pending.popLast() {
                    if view.isKind(of: listType) { addPan(to: view) }
                    pending.append(contentsOf: view.subviews)
                }
                if !recognizers.isEmpty {
                    ProbeLog.write("sensor " + String(recognizers.count))
                    let count = String(recognizers.count)
                    UserDefaults(suiteName: TapLockPreferences.domain)?
                        .set("attached:" + count, forKey: "BottomSwipeProbeSensor")
                    return
                }
            }
        }
    }

    private func addPan(to view: UIView) {
        guard !recognizers.contains(where: { $0.view === view }) else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        recognizers.append(pan)
    }

    private func geometry(for size: CGSize) -> BottomSwipeGeometry {
        var safeBottom: CGFloat = 0
        if let window = recognizers.first?.view as? UIWindow {
            safeBottom = window.safeAreaInsets.bottom
        }
        return BottomSwipeGeometry.current(size: size, safeBottom: safeBottom)
    }

    private func owns(_ gestureRecognizer: UIGestureRecognizer) -> UIPanGestureRecognizer? {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              recognizers.contains(where: { $0 === pan }) else { return nil }
        return pan
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard Thread.isMainThread,
              let pan = owns(gestureRecognizer),
              touch.type == .direct,
              let view = pan.view,
              canListen else { return false }
        let point = touch.location(in: view)
        return geometry(for: view.bounds.size).zone(for: point) != .outside
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard Thread.isMainThread,
              let pan = owns(gestureRecognizer),
              let view = pan.view,
              canListen else { return false }
        let point = pan.location(in: view)
        return geometry(for: view.bounds.size).zone(for: point) != .outside
    }

    @objc private func handle(_ pan: UIPanGestureRecognizer) {
        guard Thread.isMainThread, let view = pan.view, canListen else { return }
        let key = ObjectIdentifier(pan)
        switch pan.state {
        case .began:
            touches += 1
            ProbeLog.write("touch " + String(touches))
            UserDefaults(suiteName: TapLockPreferences.domain)?
                .set("began=\(touches)", forKey: "BottomSwipeProbeTouch")
            startPoints[key] = pan.location(in: view)
            dispatching = false
        case .ended:
            guard !dispatching, let start = startPoints.removeValue(forKey: key) else { return }
            let geometry = self.geometry(for: view.bounds.size)
            // The origin must still be inside the band; distance comes from the
            // recognizer so the pre-recognition slop is included.
            guard geometry.zone(for: start) != .outside else { return }
            let upward = -pan.translation(in: view).y
            guard geometry.tier(forUpward: upward) != .insufficient else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastFire > 1 else { return }
            lastFire = now
            dispatching = true
            defer { dispatching = false }
            ScreenshotAction.capture()
        default:
            startPoints.removeValue(forKey: key)
        }
    }
}

// A second retained dyld initializer keeps the probe out of the frozen 0.1.13
// startup files. It defers to the main queue exactly like the tap hook.
@_used
@_section("__DATA,__mod_init_func")
private var bottomSwipeInitializer: @convention(c) () -> Void = {
    DispatchQueue.main.async {
        BottomSwipeUp.shared.start()
    }
}

/// Plain-text probe log. UserDefaults is served by cfprefsd and its on-disk
/// plist lags behind, so a device-side check reads this file instead:
/// /var/mobile/Library/Preferences/taplock-probe.log
enum ProbeLog {
    static let path = "/var/mobile/Library/Preferences/taplock-probe.log"

    static func write(_ message: String) {
        let line = Date().description + " " + message + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
