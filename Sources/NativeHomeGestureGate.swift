import UIKit
import ObjectiveC
import TapLockNativeRuntime

/// M1 mechanism probe. Vetoes the system Home gesture when it starts inside the
/// bottom activation band, so `BottomSwipeUp` can own that swipe. The owning
/// class is discovered at runtime because the reference package keeps its name
/// encrypted; zero or multiple owners are treated as unsupported. Every rejection
/// path forwards to the original implementation, so the native gesture keeps
/// working when anything is missing.
enum NativeHomeGestureGate {
    private static let selector = NSSelectorFromString("shouldBeginGestureAtStartingPoint:velocity:bounds:")

    private typealias ShouldBegin = @convention(c) (AnyObject, Selector, CGPoint, CGPoint, CGRect) -> Bool

    private static var original: IMP?

    static var isInstalled: Bool { original != nil }

    static func install() {
        guard Thread.isMainThread, original == nil else { return }
        guard let type = ownerClass(),
              let method = class_getInstanceMethod(type, selector),
              matches(method) else { return }
        original = method_getImplementation(method)
        MSHookMessageEx(type, selector, unsafeBitCast(shouldBegin, to: IMP.self), &original)
    }

    private static let shouldBegin: ShouldBegin = { receiver, command, start, velocity, bounds in
        if BottomSwipeUp.shared.suppresses(start: start, bounds: bounds) { return false }
        guard let original = original else { return true }
        return unsafeBitCast(original, to: ShouldBegin.self)(receiver, command, start, velocity, bounds)
    }

    /// A single class that owns the decision method. Inherited entries are
    /// ignored, and two candidates are rejected instead of being guessed.
    private static func ownerClass() -> AnyClass? {
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return nil }
        defer { free(UnsafeMutableRawPointer(list)) }
        var owner: AnyClass?
        for index in 0..<Int(count) {
            let type: AnyClass = list[index]
            guard class_getInstanceMethod(type, selector) != nil else { continue }
            guard declares(type) else { continue }
            if owner != nil { return nil }
            owner = type
        }
        return owner
    }

    private static func declares(_ type: AnyClass) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(type, &count) else { return false }
        defer { free(methods) }
        for index in 0..<Int(count) where method_getName(methods[index]) == selector {
            return true
        }
        return false
    }

    /// BOOL(self, _cmd, CGPoint, CGPoint, CGRect). Anything else is refused
    /// before the replacement is installed.
    private static func matches(_ method: Method) -> Bool {
        guard method_getNumberOfArguments(method) == 5,
              returns(method) == "B" else { return false }
        let start = argumentType(method, 2) ?? ""
        let velocity = argumentType(method, 3) ?? ""
        let bounds = argumentType(method, 4) ?? ""
        return start.contains("CGPoint") && velocity.contains("CGPoint") && bounds.contains("CGRect")
    }

    private static func returns(_ method: Method) -> String? {
        guard let raw = method_copyReturnType(method) else { return nil }
        defer { free(raw) }
        return String(cString: raw)
    }

    private static func argumentType(_ method: Method, _ index: UInt32) -> String? {
        guard let raw = method_copyArgumentType(method, index) else { return nil }
        defer { free(raw) }
        return String(cString: raw)
    }
}
