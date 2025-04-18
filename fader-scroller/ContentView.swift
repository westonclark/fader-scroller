//
//  ContentView.swift
//  fader-scroller
//
//  Created by Weston Clark on 4/17/25.
//

import SwiftUI
import Cocoa
import ApplicationServices

struct ContentView: View {
    // Add a timer that fires every second
    // let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
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
            scrollMonitor = ScrollWheelMonitor { deltaY in
                handleScroll(deltaY: deltaY)
            }
        }
        .onDisappear {
            scrollMonitor?.cleanup()
            scrollMonitor = nil
        }
        .onReceive(timer) { _ in
            logElementUnderMouse()
        }
    }
}

func checkAccessibilityPermission() -> Bool {
    return AXIsProcessTrusted()
}

func logElementUnderMouse() {
    let mouseLocation = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first else { return }
    let point = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)

    let systemWideElement = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
    if result == .success, let element = element {
        let sliders = findAllSliders(element)
        if sliders.isEmpty {
            print("No sliders under mouse.")
        } else if let slider = findSliderUnderMouse(sliders, mousePoint: point) {
            let label = getSliderLabel(slider) ?? "(no label)"
            print("Slider under mouse: \(label)")
            // printAvailableActions(for: slider)
            // printAllAttributes(for: slider)
        } else {
            print("No slider directly under mouse (but found \(sliders.count) in subtree).")
        }
    } else {
        print("Could not get accessibility element under mouse.")
    }
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

func handleScroll(deltaY: CGFloat) {
    let mouseLocation = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first else { return }
    let point = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)

    let systemWideElement = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)
    if result == .success, let element = element {
        let sliders = findAllSliders(element)
        if let slider = findSliderUnderMouse(sliders, mousePoint: point) {

            // Determine direction
            let action = deltaY > 0 ? "AXIncrement" : "AXDecrement"

            // Linear scaling with a reasonable maximum
            let scrollMagnitude = min(abs(deltaY), 30.0) // Cap maximum scroll speed
            let scaledActions = Int(scrollMagnitude * 0.5) // Adjust this multiplier to tune sensitivity

            // Ensure at least one action for intentional scrolls
            let numActions = max(1, scaledActions)

            // Perform actions with consistent timing
            for _ in 0..<numActions {
                // performSliderAction(slider, action: action)
                AXUIElementPerformAction(slider, action as CFString)
            }
        }
    }
}

class ScrollWheelMonitor: Hashable {
    private var monitor: Any?
    private static var activeMonitors: Set<ScrollWheelMonitor> = []
    private let id = UUID() // Add a unique identifier

    // Add Hashable conformance
    static func == (lhs: ScrollWheelMonitor, rhs: ScrollWheelMonitor) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(onScroll: @escaping (CGFloat) -> Void) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            onScroll(event.scrollingDeltaY)
        }
        if let _ = monitor {
            ScrollWheelMonitor.activeMonitors.insert(self)
        }
    }

    func cleanup() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            ScrollWheelMonitor.activeMonitors.remove(self)
            self.monitor = nil
        }
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

// func printAvailableActions(for element: AXUIElement) {
//     var actionsValue: CFTypeRef?
//     if AXUIElementCopyAttributeValue(element, "AXActions" as CFString, &actionsValue) == .success,
//        let actions = actionsValue as? [String] {
//         print("Available actions for element:")
//         for action in actions {
//             print(" - \(action)")
//         }
//     } else {
//         print("No actions available for this element.")
//     }
// }

// func printAllAttributes(for element: AXUIElement) {
//     var names: CFArray?
//     let result = AXUIElementCopyAttributeNames(element, &names)
//     if result == .success, let names = names as? [String] {
//         print("Available attributes for element:")
//         for attr in names {
//             print(" - \(attr)")
//         }
//     } else {
//         print("No attributes available for this element.")
//     }
// }

#Preview {
    ContentView()
}
