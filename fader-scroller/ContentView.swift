//
//  ContentView.swift
//  fader-scroller
//
//  Created by Weston Clark on 4/17/25.
//

import SwiftUI
import Cocoa
import ApplicationServices
import CoreGraphics

struct ContentView: View {
    // Add a timer that fires every second
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State private var scrollMonitor: ScrollWheelMonitor?

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Fader Scroller")
            Text("Logging element under mouse every second...")
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .padding()
        .onAppear {
            scrollMonitor = ScrollWheelMonitor { deltaY, slider in
                _ = getSliderLabel(slider) ?? "(no label)"
                let action = deltaY > 0 ? kAXIncrementAction as String : kAXDecrementAction as String
                let scrollMagnitude = min(abs(deltaY), 30.0)
                let scaledActions = Int(scrollMagnitude * 0.25)
                let numActions = max(1, scaledActions)
                for _ in 0..<numActions {
                    _ = AXUIElementPerformAction(slider, action as CFString)
                }
            }
        }
        .onDisappear {
            scrollMonitor?.cleanup()
            scrollMonitor = nil
        }
        .onReceive(timer) { _ in
            // logElementUnderMouse()
        }
    }
}

func checkAccessibilityPermission() -> Bool {
    return AXIsProcessTrusted()
}

// func logElementUnderMouse() {
//     let mouseLocation = NSEvent.mouseLocation
//     guard let screen = NSScreen.screens.first else { return }
//     let point = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)

//     let systemWideElement = AXUIElementCreateSystemWide()
//     var element: AXUIElement?
//     let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
//     if result == .success, let element = element {
//         let sliders = findAllSliders(element)
//         if sliders.isEmpty {
//             // No sliders under mouse.
//         } else if let slider = findSliderUnderMouse(sliders, mousePoint: point) {
//             // Slider under mouse found.
//         } else {
//             // No slider directly under mouse (but found some in subtree).
//         }
//     } else {
//         // Could not get accessibility element under mouse.
//     }
// }

func findSliderElement(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
    var role: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
       let roleStr = role as? String, roleStr == kAXSliderRole as String {
        return element
    }
    // Recursively check children
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
       let childrenArray = children as? [AXUIElement] {
        for child in childrenArray {
            if let found = findSliderElement(child, depth: depth + 1) {
                return found
            }
        }
    }
    return nil
}

func getSliderLabel(_ slider: AXUIElement) -> String? {
    var title: CFTypeRef?
    if AXUIElementCopyAttributeValue(slider, kAXTitleAttribute as CFString, &title) == .success,
       let titleStr = title as? String {
        return titleStr
    }
    // Try description if title is not available
    var desc: CFTypeRef?
    if AXUIElementCopyAttributeValue(slider, kAXDescriptionAttribute as CFString, &desc) == .success,
       let descStr = desc as? String {
        return descStr
    }
    return nil
}

func findAllSliders(_ element: AXUIElement) -> [AXUIElement] {
    var sliders: [AXUIElement] = []
    var role: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
       let roleStr = role as? String, roleStr == kAXSliderRole as String {
        sliders.append(element)
    }
    // Recursively check children
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
       let childrenArray = children as? [AXUIElement] {
        for child in childrenArray {
            sliders.append(contentsOf: findAllSliders(child))
        }
    }
    return sliders
}

func getSliderFrame(_ slider: AXUIElement) -> CGRect? {
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(slider, kAXPositionAttribute as CFString, &posValue) == .success,
       AXUIElementCopyAttributeValue(slider, kAXSizeAttribute as CFString, &sizeValue) == .success {
        let pos = posValue as! AXValue
        let size = sizeValue as! AXValue
        var point = CGPoint.zero
        var sizeStruct = CGSize.zero
        AXValueGetValue(pos, .cgPoint, &point)
        AXValueGetValue(size, .cgSize, &sizeStruct)
        return CGRect(origin: point, size: sizeStruct)
    }
    return nil
}

func findSliderUnderMouse(_ sliders: [AXUIElement], mousePoint: CGPoint) -> AXUIElement? {
    for slider in sliders {
        if let frame = getSliderFrame(slider), frame.contains(mousePoint) {
            return slider
        }
    }
    return nil
}

// Helper function to get the parent of an element
func getParentElement(_ element: AXUIElement) -> AXUIElement? {
    var parent: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success {
        return (parent as! AXUIElement?)
    }
    return nil
}

class ScrollWheelMonitor: Hashable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static var activeMonitors: Set<ScrollWheelMonitor> = []
    private let id = UUID()
    private let onScroll: (CGFloat, AXUIElement) -> Void

    // --- Optimization: Cache the last targeted slider ---
    private var cachedSlider: AXUIElement?
    private var cacheTimestamp: Date?
    private let cacheTimeout: TimeInterval = 0.3 // Invalidate cache after 0.3 seconds of inactivity

    static func == (lhs: ScrollWheelMonitor, rhs: ScrollWheelMonitor) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(onScroll: @escaping (CGFloat, AXUIElement) -> Void) {
        self.onScroll = onScroll
        setupEventTap()
        ScrollWheelMonitor.activeMonitors.insert(self)
    }

    private func invalidateCache() {
        // Helper to clear cache
        cachedSlider = nil
        cacheTimestamp = nil
    }

    private func setupEventTap() {
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }
                let monitor = Unmanaged<ScrollWheelMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .scrollWheel {
                    let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                    guard deltaY != 0.0 else {
                        return Unmanaged.passRetained(event)
                    }

                    let mouseLocation = NSEvent.mouseLocation
                    guard let screen = NSScreen.screens.first else {
                        monitor.invalidateCache()
                        return Unmanaged.passRetained(event)
                    }
                    let point = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)
                    let now = Date()

                    if let cached = monitor.cachedSlider,
                       let lastCacheTime = monitor.cacheTimestamp,
                       now.timeIntervalSince(lastCacheTime) < monitor.cacheTimeout {
                        if let frame = getSliderFrame(cached), frame.contains(point) {
                            monitor.cacheTimestamp = now
                            DispatchQueue.main.async {
                                monitor.onScroll(deltaY, cached)
                            }
                            return nil
                        } else {
                            monitor.invalidateCache()
                        }
                    } else if monitor.cachedSlider != nil {
                        monitor.invalidateCache()
                    }

                    let systemWideElement = AXUIElementCreateSystemWide()
                    var elementUnderMouse: AXUIElement?
                    let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &elementUnderMouse)

                    if result == .success, let element = elementUnderMouse {
                        var targetSlider: AXUIElement? = nil
                        var searchElement: AXUIElement? = element

                        for _ in 0..<3 {
                            guard let currentSearchElement = searchElement else { break }
                            let sliders = findAllSliders(currentSearchElement)
                            if let slider = findSliderUnderMouse(sliders, mousePoint: point) {
                                targetSlider = slider
                                break
                            }
                            searchElement = getParentElement(currentSearchElement)
                        }

                        if let slider = targetSlider {
                            monitor.cachedSlider = slider
                            monitor.cacheTimestamp = now
                            DispatchQueue.main.async {
                                monitor.onScroll(deltaY, slider)
                            }
                            return nil
                        } else {
                            monitor.invalidateCache()
                        }
                    } else {
                        monitor.invalidateCache()
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr)

        if let eventTap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }

    func cleanup() {
        invalidateCache()
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        ScrollWheelMonitor.activeMonitors.remove(self)
    }

    deinit {
        cleanup()
    }

    static func cleanupAllMonitors() {
        for monitor in activeMonitors {
            monitor.cleanup()
        }
        activeMonitors.removeAll()
    }
}

#Preview {
    ContentView()
}
