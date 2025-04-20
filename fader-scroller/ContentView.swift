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
    @State private var isPolarityReversed: Bool = false

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Fader Scroller")
            Text("Logging element under mouse every second...")
                .font(.footnote)
                .foregroundColor(.gray)
            Toggle("Reverse Polarity", isOn: $isPolarityReversed)
                .padding(.top)
            Button("Re-sync") {
                invalidateScrollMonitorCache()
            }
            .padding(.top, 8)
        }
        .padding()
        .onAppear {
            scrollMonitor = ScrollWheelMonitor { deltaY, slider in
                handleScroll(deltaY: deltaY, slider: slider)
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

    func handleScroll(deltaY: CGFloat, slider: AXUIElement) {
        let effectiveDeltaY = isPolarityReversed ? -deltaY : deltaY
        _ = getSliderLabel(slider) ?? "(no label)"
        let action = effectiveDeltaY > 0 ? kAXIncrementAction as String : kAXDecrementAction as String
        let scrollMagnitude = min(abs(effectiveDeltaY), 30.0)
        let scaledActions = Int(scrollMagnitude * 0.25)
        let numActions = max(1, scaledActions)
        for _ in 0..<numActions {
            _ = AXUIElementPerformAction(slider, action as CFString)
        }
    }

    func invalidateScrollMonitorCache() {
        scrollMonitor?.invalidateCache()
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

// Helper to get frame for any element (used for container and slider)
func getElementFrame(_ element: AXUIElement) -> CGRect? {
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?

    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else {
        return nil
    }

    // Ensure the values are non-nil AND are actually AXValue types before proceeding
    guard let pos = posValue, let size = sizeValue,
          CFGetTypeID(pos) == AXValueGetTypeID(), // Check type ID
          CFGetTypeID(size) == AXValueGetTypeID() else { // Check type ID
        print("Retrieved position/size attribute is not an AXValue")
        return nil
    }

    // Now we know they are AXValue, but still need to check the *specific* AXValue type
    guard AXValueGetType(pos as! AXValue) == .cgPoint, // Cast is now safer
          AXValueGetType(size as! AXValue) == .cgSize else { // Cast is now safer
        print("AXValue is not of type CGPoint or CGSize")
        return nil
    }

    var point = CGPoint.zero
    var sizeStruct = CGSize.zero

    // Use the unsafeBitCast pattern which is common for CF -> Swift bridging
    // when the type is known and checked.
    guard AXValueGetValue(pos as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &sizeStruct) else {
        print("Failed to convert AXValue to CGPoint/CGSize")
        return nil
    }

    return CGRect(origin: point, size: sizeStruct)
}

func findSliderUnderMouse(_ sliders: [AXUIElement], mousePoint: CGPoint) -> AXUIElement? {
    for slider in sliders {
        // Use the generic getElementFrame here
        if let frame = getElementFrame(slider), frame.contains(mousePoint) {
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

    // Simplified cache structure
    private struct CachedFader {
        let element: AXUIElement
        let frame: CGRect
        let timestamp: Date
    }
    private var cachedFaders: [CachedFader] = []
    private let cacheTimeout: TimeInterval = 2.0  // Increased timeout since we're caching more faders

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

    func invalidateCache() {
        cachedFaders.removeAll()
        print("Fader cache invalidated")
    }

    private func setupEventTap() {
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<ScrollWheelMonitor>.fromOpaque(refcon).takeUnretainedValue()

                if type == .scrollWheel {
                    let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                    guard deltaY != 0.0 else { return Unmanaged.passRetained(event) }

                    let mouseLocation = NSEvent.mouseLocation
                    guard let screen = NSScreen.screens.first else {
                        monitor.invalidateCache()
                        return Unmanaged.passRetained(event)
                    }
                    let point = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)
                    let now = Date()

                    // First check the cache
                    if !monitor.cachedFaders.isEmpty {
                        // Remove expired cache entries
                        monitor.cachedFaders.removeAll {
                            now.timeIntervalSince($0.timestamp) > monitor.cacheTimeout
                        }

                        // Check if mouse is over any cached fader
                        if let cachedFader = monitor.cachedFaders.first(where: { $0.frame.contains(point) }) {
                            // Verify the fader is still valid by checking its frame
                            if let currentFrame = getElementFrame(cachedFader.element),
                               currentFrame == cachedFader.frame {
                                DispatchQueue.main.async {
                                    monitor.onScroll(deltaY, cachedFader.element)
                                }
                                return nil // Consume event
                            }
                        }
                    }

                    // Direct lookup for element under mouse
                    let systemWideElement = AXUIElementCreateSystemWide()
                    var elementUnderMouse: AXUIElement?
                    let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &elementUnderMouse)

                    if result == .success, let element = elementUnderMouse {
                        // Check if element is a slider
                        var role: CFTypeRef?
                        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                           let roleStr = role as? String,
                           roleStr == kAXSliderRole as String {
                            // Found a slider directly!
                            if let frame = getElementFrame(element) {
                                // Add to cache
                                monitor.cachedFaders.append(CachedFader(
                                    element: element,
                                    frame: frame,
                                    timestamp: now
                                ))
                                DispatchQueue.main.async {
                                    monitor.onScroll(deltaY, element)
                                }
                                return nil // Consume event
                            }
                        }

                        // If not a slider directly, do a quick search in nearby elements
                        var nearbySliders: [AXUIElement] = []
                        findAllSlidersRecursive(element, &nearbySliders, depth: 0, maxDepth: 3)

                        for slider in nearbySliders {
                            if let frame = getElementFrame(slider) {
                                monitor.cachedFaders.append(CachedFader(
                                    element: slider,
                                    frame: frame,
                                    timestamp: now
                                ))

                                if frame.contains(point) {
                                    DispatchQueue.main.async {
                                        monitor.onScroll(deltaY, slider)
                                    }
                                    return nil // Consume event
                                }
                            }
                        }
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

func logParentChainToSlider(from element: AXUIElement, mousePoint: CGPoint) {
    var current: AXUIElement? = element
    var depth = 0
    var foundSlider = false

    while let el = current, depth < 10 { // Limit to 10 to avoid infinite loops
        var role: CFTypeRef?
        var desc: CFTypeRef?
        let roleStr = (AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success) ? (role as? String ?? "nil") : "error"
        let descStr = (AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &desc) == .success) ? (desc as? String ?? "nil") : "error"
        print("Depth \(depth): Role = \(roleStr), Description = \(descStr)")

        if roleStr == kAXSliderRole as String {
            print("Found slider at depth \(depth)!")
            foundSlider = true
            break
        }
        current = getParentElement(el)
        depth += 1
    }
    if !foundSlider {
        print("No slider found in parent chain up to depth \(depth)")
    }
}

func logSiblingsAndChildren(of element: AXUIElement) {
    // Log children
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
       let childrenArray = children as? [AXUIElement] {
        print("Children of current element:")
        for (i, child) in childrenArray.enumerated() {
            var role: CFTypeRef?
            let roleStr = (AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success) ? (role as? String ?? "nil") : "error"
            print("  Child \(i): Role = \(roleStr)")
        }
    } else {
        print("No children for current element.")
    }

    // Log siblings
    if let parent = getParentElement(element) {
        var siblings: CFTypeRef?
        if AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &siblings) == .success,
           let siblingsArray = siblings as? [AXUIElement] {
            print("Siblings of current element:")
            for (i, sibling) in siblingsArray.enumerated() {
                var role: CFTypeRef?
                let roleStr = (AXUIElementCopyAttributeValue(sibling, kAXRoleAttribute as CFString, &role) == .success) ? (role as? String ?? "nil") : "error"
                print("  Sibling \(i): Role = \(roleStr)")
            }
        }
    } else {
        print("No parent, so no siblings.")
    }
}

// Recursive slider search with depth limit
func findAllSlidersRecursive(_ element: AXUIElement, _ sliders: inout [AXUIElement], depth: Int, maxDepth: Int) {
    if depth > maxDepth { return } // Stop recursion if too deep

    var role: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
       let roleStr = role as? String {

        if roleStr == kAXSliderRole as String {
            sliders.append(element)
            // Don't search children of sliders themselves typically
            return
        }

        // Recurse into children regardless of parent type, but respect maxDepth
        var children: CFTypeRef?
        // Check if children attribute exists before trying to copy it
        var _: DarwinBoolean = false
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let childrenArray = children as? [AXUIElement] {
             // print("Depth \(depth): Element \(roleStr) has \(childrenArray.count) children. MaxDepth: \(maxDepth)") // Debug
            for child in childrenArray {
                findAllSlidersRecursive(child, &sliders, depth: depth + 1, maxDepth: maxDepth)
            }
        }
         // else { print("Depth \(depth): Element \(roleStr) has no children or failed to get.")} // Debug
    }
    // else { print("Depth \(depth): Failed to get role for element.") } // Debug
}

#Preview {
    ContentView()
}
