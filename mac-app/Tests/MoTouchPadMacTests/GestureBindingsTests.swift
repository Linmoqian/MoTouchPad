import Foundation
import XCTest
@testable import MoTouchPadCore
@testable import MoTouchPadMac

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

@MainActor
final class GestureBindingsTests: XCTestCase {
    func testDefaultsAndCodableRoundTrip() throws {
        XCTAssertEqual(GestureBindings.defaults.binding(for: .pageBack)?.displayName, "⌘[")
        XCTAssertEqual(GestureBindings.defaults.binding(for: .missionControl)?.displayName, "⌃↑")
        XCTAssertNil(GestureBindings.defaults.binding(for: .rotateClockwise))
        XCTAssertNil(GestureBindings.defaults.binding(for: .smartZoom))

        let data = try JSONEncoder().encode(GestureBindings.defaults)
        XCTAssertEqual(try JSONDecoder().decode(GestureBindings.self, from: data), .defaults)
    }

    func testPreferencesPersistAndCanRestoreDefaults() {
        let suiteName = "MoTouchPadTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = GesturePreferences(defaults: defaults)
        let custom = KeyboardShortcut(keyCode: 2, modifiers: [.command, .option])
        preferences.set(custom, for: .rotateClockwise)
        XCTAssertEqual(GesturePreferences(defaults: defaults).bindings.binding(for: .rotateClockwise), custom)

        preferences.resetToDefaults()
        XCTAssertEqual(preferences.bindings, .defaults)
    }

    func testExecutorUsesConfiguredShortcutsAndSkipsUnboundCommands() {
        let sink = RecordingSink()
        var bindings = GestureBindings.defaults
        bindings.rotateClockwise = nil
        let executor = GestureActionExecutor(sink: sink, bindings: bindings)

        executor.execute([
            .move(dx: 0.1, dy: -0.2, sensitivityPercent: 125),
            .click(button: .primary, count: 2),
            .drag(phase: .began, dx: 0, dy: 0, sensitivityPercent: 100),
            .drag(phase: .moved, dx: 0.02, dy: 0.03, sensitivityPercent: 100),
            .scroll(vertical: 2, horizontal: -1),
            .command(.zoomIn, repeats: 2),
            .command(.rotateClockwise, repeats: 1),
            .drag(phase: .ended, dx: 0, dy: 0, sensitivityPercent: 100)
        ])
        executor.reset()

        XCTAssertEqual(sink.events, [
            "move 0.1 -0.2 125",
            "click primary 2",
            "drag-begin",
            "drag 0.02 0.03 100",
            "scroll 2 -1",
            "shortcut ⌘=",
            "shortcut ⌘=",
            "drag-end",
            "reset"
        ])
    }
}

private final class RecordingSink: MacInputSink {
    var events: [String] = []

    func moveNormalized(dx: Float, dy: Float, sensitivityPercent: Int) {
        events.append("move \(dx) \(dy) \(sensitivityPercent)")
    }

    func click(button: PointerButton, count: Int) {
        let label = button == .primary ? "primary" : "secondary"
        events.append("click \(label) \(count)")
    }

    func beginPrimaryDrag() {
        events.append("drag-begin")
    }

    func dragNormalized(dx: Float, dy: Float, sensitivityPercent: Int) {
        events.append("drag \(dx) \(dy) \(sensitivityPercent)")
    }

    func endPrimaryDrag() {
        events.append("drag-end")
    }

    func scroll(vertical: Int, horizontal: Int) {
        events.append("scroll \(vertical) \(horizontal)")
    }

    func send(shortcut: KeyboardShortcut) {
        events.append("shortcut \(shortcut.displayName)")
    }

    func reset() {
        events.append("reset")
    }
}
