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

// Accessibility role constants
let kAXScrollArea = "AXScrollArea" as CFString
let kAXGroup = "AXGroup" as CFString

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
        .onReceive(timer) { _ in
            // Check and update cache every second
            scrollMonitor?.checkAndUpdateCache()
        }
        .onDisappear {
            scrollMonitor?.cleanup()
            scrollMonitor = nil
        }
    }

    func handleScroll(deltaY: CGFloat, slider: AXUIElement) {
        let effectiveDeltaY = isPolarityReversed ? -deltaY : deltaY
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

// func findAllSliders(_ element: AXUIElement) -> [AXUIElement] {
//     var sliders: [AXUIElement] = []
//     var role: CFTypeRef?
//     if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
//        let roleStr = role as? String, roleStr == kAXSliderRole as String {
//         sliders.append(element)
//     }
//     // Recursively check children
//     var children: CFTypeRef?
//     if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
//        let childrenArray = children as? [AXUIElement] {
//         for child in childrenArray {
//             sliders.append(contentsOf: findAllSliders(child))
//         }
//     }
//     return sliders
// }

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
          CFGetTypeID(size) == AXValueGetTypeID() else {
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

// func findSliderUnderMouse(_ sliders: [AXUIElement], mousePoint: CGPoint) -> AXUIElement? {
//     for slider in sliders {
//         // Use the generic getElementFrame here
//         if let frame = getElementFrame(slider), frame.contains(mousePoint) {
//             return slider
//         }
//     }
//     return nil
// }

// Helper function to get the parent of an element
func getParentElement(_ element: AXUIElement) -> AXUIElement? {
    var parent: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success {
        return (parent as! AXUIElement?)
    }
    return nil
}

// New structure to hold fader info
struct FaderInfo {
    let element: AXUIElement
    let frame: CGRect
    let xPosition: CGFloat
}

// Function to get application element from any element
func getApplicationElement(_ element: AXUIElement) -> AXUIElement? {
    var current: AXUIElement? = element
    while let el = current {
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String,
           roleStr == kAXApplicationRole as String {
            return el
        }
        current = getParentElement(el)
    }
    return nil
}

// Function to get all faders in sorted order
func getAllSortedFaders() -> [FaderInfo] {
    let systemWideElement = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let mouseLocation = NSEvent.mouseLocation

    // Get element under mouse first to find the application
    let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(mouseLocation.x), Float(mouseLocation.y), &element)
    guard result == .success,
          let element = element,
          let appElement = getApplicationElement(element) else {
        return []
    }

    // Get all windows
    var children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &children) == .success,
          let childrenArray = children as? [AXUIElement] else {
        return []
    }

    // Find the Mix window
    var mixWindow: AXUIElement?
    for child in childrenArray {
        var role: CFTypeRef?
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
           AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title) == .success,
           let roleStr = role as? String,
           let titleStr = title as? String,
           roleStr == kAXWindowRole as String,
           titleStr.hasPrefix("Mix:") {
            mixWindow = child
            break
        }
    }

    guard let mixWindow = mixWindow else {
        return []
    }

    // Get the channels container from the Mix window
    var mixChildren: CFTypeRef?
    guard AXUIElementCopyAttributeValue(mixWindow, kAXChildrenAttribute as CFString, &mixChildren) == .success,
          let mixChildrenArray = mixChildren as? [AXUIElement] else {
        return []
    }

    // Find all track groups (they have role AXGroup and title containing "Audio")
    var trackGroups: [AXUIElement] = []
    for child in mixChildrenArray {
        var role: CFTypeRef?
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
           AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &title) == .success,
           let roleStr = role as? String,
           let titleStr = title as? String,
           roleStr == kAXGroup as String,
           titleStr.contains("Audio") {
            trackGroups.append(child)
        }
    }

    // Get all faders from each track group
    var allFaders: [AXUIElement] = []
    for group in trackGroups {
        var groupChildren: CFTypeRef?
        if AXUIElementCopyAttributeValue(group, kAXChildrenAttribute as CFString, &groupChildren) == .success,
           let children = groupChildren as? [AXUIElement] {
            // Look for sliders in this group
            for child in children {
                var role: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role) == .success,
                   let roleStr = role as? String,
                   roleStr == kAXSliderRole as String {
                    allFaders.append(child)
                }
            }
        }
    }

    // Convert to FaderInfo, only including volume faders
    let allFaderInfos = allFaders.compactMap { fader -> FaderInfo? in
        var title: CFTypeRef?
        var type: AnyObject?
        var orientation: CFTypeRef?

        // Get all relevant attributes
        AXUIElementCopyAttributeValue(fader, kAXTitleAttribute as CFString, &title)
        AXUIElementCopyAttributeValue(fader, kAXRoleDescriptionAttribute as CFString, &type)
        AXUIElementCopyAttributeValue(fader, kAXOrientationAttribute as CFString, &orientation)

        let titleStr = title as? String ?? "nil"
        let typeStr = type as? String ?? "nil"
        let orientationStr = orientation as? String ?? "nil"

        // Check if this is a volume fader
        if titleStr == "Volume" && typeStr == "Fader" && orientationStr == "AXVerticalOrientation" {
            guard let frame = getElementFrame(fader) else { return nil }
            return FaderInfo(element: fader, frame: frame, xPosition: frame.minX)
        }
        return nil
    }

    // Only keep the first fader of each pair (the actual fader control)
    return stride(from: 0, to: allFaderInfos.count, by: 2).map { allFaderInfos[$0] }
}

// Find the correct fader based on X position and verify Y position is within bounds
func findFaderAtPosition(_ x: CGFloat, _ y: CGFloat, in faders: [FaderInfo]) -> AXUIElement? {
    guard !faders.isEmpty else { return nil }

    // If we only have one fader, verify Y position
    if faders.count == 1 {
        return faders[0].frame.minY <= y && y <= faders[0].frame.maxY ? faders[0].element : nil
    }

    // Calculate the width of each fader section
    let firstX = faders[0].xPosition
    let lastX = faders[faders.count - 1].xPosition
    let sectionWidth = (lastX - firstX) / CGFloat(faders.count - 1)

    // Calculate the index based on X position
    var index = Int(round((x - firstX) / sectionWidth))

    // Clamp the index to valid range
    index = max(0, min(index, faders.count - 1))

    // Verify Y position is within the fader's bounds
    let fader = faders[index]
    if fader.frame.minY <= y && y <= fader.frame.maxY {
        return fader.element
    }

    return nil
}

class ScrollWheelMonitor: Hashable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private static var activeMonitors: Set<ScrollWheelMonitor> = []
    private let id = UUID()
    private let onScroll: (CGFloat, AXUIElement) -> Void
    private var cache: WindowedCache?
    private var lastProcessedFader: AXUIElement?

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
        cache = nil
        lastProcessedFader = nil
    }

    private func checkReferencePositionAndUpdateCache() {
        guard let cache = cache,
              !cache.visibleFaders.isEmpty else {
            updateCacheIfNeeded()
            return
        }

        // Get the current position of our reference fader (first fader)
        let referenceFader = cache.visibleFaders[0].element
        if let frame = getElementFrame(referenceFader) {
            let currentPosition = CGPoint(x: frame.minX, y: frame.minY)

            // If reference fader has moved significantly (e.g., more than 1 pixel)
            if abs(currentPosition.x - cache.referenceFaderPosition.x) > 1.0 ||
               abs(currentPosition.y - cache.referenceFaderPosition.y) > 1.0 {
                print("Reference fader position changed - updating cache with new positions")

                // Instead of just invalidating, immediately get new fader positions
                let allFaders = getAllSortedFaders()
                if !allFaders.isEmpty {
                    // Create new cache with updated positions
                    self.cache = WindowedCache(
                        visibleFaders: allFaders,
                        timestamp: Date(),
                        referenceFaderPosition: CGPoint(x: allFaders[0].frame.minX, y: allFaders[0].frame.minY)
                    )
                } else {
                    // If we couldn't get new faders, invalidate cache
                    invalidateCache()
                }
            }
        } else {
            // If we can't get the frame of our reference fader, something's wrong
            print("Could not get reference fader frame - invalidating cache")
            invalidateCache()
        }
    }

    private func updateCacheIfNeeded() {
        if cache != nil {
            checkReferencePositionAndUpdateCache()
            return
        }

        let now = Date()

        // Get all faders
        let allFaders = getAllSortedFaders()

        // If we have no faders, nothing to cache
        guard !allFaders.isEmpty else { return }

        // Store the position of our reference fader (first fader)
        let referencePosition = CGPoint(x: allFaders[0].frame.minX, y: allFaders[0].frame.minY)

        cache = WindowedCache(
            visibleFaders: allFaders,
            timestamp: now,
            referenceFaderPosition: referencePosition
        )
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
                    guard let screen = NSScreen.screens.first else { return Unmanaged.passRetained(event) }

                    // Quick check if we're in Pro Tools and the Mix window
                    let systemWideElement = AXUIElementCreateSystemWide()
                    var element: AXUIElement?
                    let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(mouseLocation.x), Float(mouseLocation.y), &element)

                    guard result == .success,
                          let element = element,
                          let appElement = getApplicationElement(element) else {
                        return Unmanaged.passRetained(event)
                    }

                    // Quick check for Pro Tools
                    var appTitle: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &appTitle) == .success,
                          let titleStr = appTitle as? String,
                          titleStr == "Pro Tools" else {
                        return Unmanaged.passRetained(event)
                    }

                    // Check if we're in a window
                    var window: AXUIElement?
                    var parent: AXUIElement? = element
                    while let currentElement = parent {
                        var role: CFTypeRef?
                        if AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &role) == .success,
                           let roleStr = role as? String,
                           roleStr == kAXWindowRole as String {
                            window = currentElement
                            break
                        }
                        parent = getParentElement(currentElement)
                    }

                    // Verify Mix window
                    guard let window = window else { return Unmanaged.passRetained(event) }
                    var windowTitle: CFTypeRef?
                    guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &windowTitle) == .success,
                          let titleStr = windowTitle as? String,
                          titleStr.hasPrefix("Mix:") else {
                        return Unmanaged.passRetained(event)
                    }

                    let y = screen.frame.height - mouseLocation.y

                    // Update cache if needed
                    monitor.updateCacheIfNeeded()

                    // Try to reuse last processed fader if we're still in the same position
                    if let lastFader = monitor.lastProcessedFader,
                       let frame = getElementFrame(lastFader),
                       frame.contains(CGPoint(x: mouseLocation.x, y: y)) {
                        DispatchQueue.main.async {
                            monitor.onScroll(CGFloat(deltaY), lastFader)
                        }
                        return nil
                    }

                    // Find new fader using cached faders
                    if let cache = monitor.cache,
                       let fader = findFaderAtPosition(mouseLocation.x, y, in: cache.visibleFaders) {
                        monitor.lastProcessedFader = fader
                        DispatchQueue.main.async {
                            monitor.onScroll(CGFloat(deltaY), fader)
                        }
                        return nil
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

    // Make this public so it can be called from ContentView
    func checkAndUpdateCache() {
        checkReferencePositionAndUpdateCache()
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

// // Recursive slider search with depth limit
// func findAllSlidersRecursive(_ element: AXUIElement, _ sliders: inout [AXUIElement], depth: Int, maxDepth: Int) {
//     if depth > maxDepth { return } // Stop recursion if too deep

//     var role: CFTypeRef?
//     if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
//        let roleStr = role as? String {

//         if roleStr == kAXSliderRole as String {
//             sliders.append(element)
//             // Don't search children of sliders themselves typically
//             return
//         }

//         // Recurse into children regardless of parent type, but respect maxDepth
//         var children: CFTypeRef?
//         // Check if children attribute exists before trying to copy it
//         var _: DarwinBoolean = false
//         if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
//            let childrenArray = children as? [AXUIElement] {
//              // print("Depth \(depth): Element \(roleStr) has \(childrenArray.count) children. MaxDepth: \(maxDepth)") // Debug
//             for child in childrenArray {
//                 findAllSlidersRecursive(child, &sliders, depth: depth + 1, maxDepth: maxDepth)
//             }
//         }
//          // else { print("Depth \(depth): Element \(roleStr) has no children or failed to get.")} // Debug
//     }
//     // else { print("Depth \(depth): Failed to get role for element.") } // Debug
// }

struct WindowedCache {
    let visibleFaders: [FaderInfo]
    let timestamp: Date
    let referenceFaderPosition: CGPoint  // Store position of first fader as reference
}

// Helper function to find scroll area
private func findScrollArea(fromElement: AXUIElement) -> AXUIElement? {
    var current: AXUIElement? = fromElement
    while let el = current {
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String,
           roleStr == kAXScrollArea as String {
            return el
        }
        current = getParentElement(el)
    }
    return nil
}

#Preview {
    ContentView()
}
