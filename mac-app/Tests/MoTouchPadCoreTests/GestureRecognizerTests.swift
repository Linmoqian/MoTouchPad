import XCTest
@testable import MoTouchPadCore

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

final class GestureRecognizerTests: XCTestCase {
    func testSingleFingerTapAndDoubleTapEmitPrimaryClicks() {
        let gestures = GestureRecognizer()
        XCTAssertTrue(gestures.feed(frame(contacts: [touch(1, 0.5, 0.5)], at: 0), now: 0).isEmpty)
        XCTAssertEqual(gestures.feed(frame(contacts: [up(1, 0.5, 0.5)], at: 100), now: 0.1),
                       [.click(button: .primary, count: 1)])
        XCTAssertTrue(gestures.feed(frame(contacts: [touch(1, 0.5, 0.5)], at: 180), now: 0.18).isEmpty)
        XCTAssertEqual(gestures.feed(frame(contacts: [up(1, 0.5, 0.5)], at: 250), now: 0.25),
                       [.click(button: .primary, count: 1)])
    }

    func testTwoFingerTapDelaysSecondaryClickAndDoubleTapUsesSmartZoom() {
        let gestures = GestureRecognizer()
        let contacts = [touch(1, 0.4, 0.5), touch(2, 0.6, 0.5)]
        XCTAssertTrue(gestures.feed(frame(contacts: contacts, at: 0), now: 0).isEmpty)
        XCTAssertTrue(gestures.feed(frame(contacts: contacts.map(release), at: 100), now: 0.1).isEmpty)
        XCTAssertEqual(gestures.flushPending(now: 0.41), [.click(button: .secondary, count: 1)])

        XCTAssertTrue(gestures.feed(frame(contacts: contacts, at: 500), now: 0.5).isEmpty)
        XCTAssertTrue(gestures.feed(frame(contacts: contacts.map(release), at: 600), now: 0.6).isEmpty)
        XCTAssertTrue(gestures.feed(frame(contacts: contacts, at: 700), now: 0.7).isEmpty)
        XCTAssertEqual(gestures.feed(frame(contacts: contacts.map(release), at: 800), now: 0.8),
                       [.command(.smartZoom, repeats: 1)])

        let sequentialRelease = GestureRecognizer()
        XCTAssertTrue(sequentialRelease.feed(frame(contacts: contacts, at: 0), now: 0).isEmpty)
        XCTAssertTrue(sequentialRelease.feed(frame(contacts: [up(1, 0.4, 0.5), touch(2, 0.6, 0.5)], at: 50), now: 0.05).isEmpty)
        XCTAssertTrue(sequentialRelease.feed(frame(contacts: [up(2, 0.6, 0.5)], at: 100), now: 0.1).isEmpty)
        XCTAssertEqual(sequentialRelease.flushPending(now: 0.41), [.click(button: .secondary, count: 1)])
    }

    func testTwoFingerScrollPageNavigationPinchAndRotation() {
        let scroll = GestureRecognizer()
        let base = [touch(1, 0.4, 0.4), touch(2, 0.6, 0.4)]
        _ = scroll.feed(frame(contacts: base, at: 0))
        XCTAssertEqual(scroll.feed(frame(contacts: [touch(1, 0.4, 0.5), touch(2, 0.6, 0.5)], at: 100)),
                       [.scroll(vertical: 4, horizontal: 0)])

        let page = GestureRecognizer()
        _ = page.feed(frame(contacts: [touch(1, 0.4, 0.5), touch(2, 0.6, 0.5)], at: 0))
        XCTAssertEqual(page.feed(frame(contacts: [touch(1, 0.55, 0.5), touch(2, 0.75, 0.5)], at: 100)),
                       [.command(.pageBack, repeats: 1)])

        let horizontal = GestureRecognizer()
        _ = horizontal.feed(frame(contacts: [touch(1, 0.4, 0.5), touch(2, 0.6, 0.5)], at: 0))
        XCTAssertEqual(horizontal.feed(frame(contacts: [touch(1, 0.43, 0.5), touch(2, 0.63, 0.5)], at: 150)),
                       [.scroll(vertical: 0, horizontal: 1)])

        let pinch = GestureRecognizer()
        _ = pinch.feed(frame(contacts: [touch(1, 0.4, 0.5), touch(2, 0.6, 0.5)], at: 0))
        XCTAssertEqual(pinch.feed(frame(contacts: [touch(1, 0.3, 0.5), touch(2, 0.7, 0.5)], at: 100)),
                       [.command(.zoomIn, repeats: 24)])

        let rotate = GestureRecognizer()
        _ = rotate.feed(frame(contacts: [touch(1, 0.4, 0.5), touch(2, 0.6, 0.5)], at: 0))
        XCTAssertEqual(rotate.feed(frame(contacts: [touch(1, 0.5, 0.4), touch(2, 0.5, 0.6)], at: 100)),
                       [.command(.rotateClockwise, repeats: 6)])
    }

    func testThreeFingerLookupSwipeAndDrag() {
        let lookup = GestureRecognizer()
        let contacts = threeContacts(y: 0.5)
        _ = lookup.feed(frame(contacts: contacts, at: 0))
        XCTAssertEqual(lookup.feed(frame(contacts: contacts.map(release), at: 100)),
                       [.command(.lookUp, repeats: 1)])

        let sequentialLookup = GestureRecognizer()
        XCTAssertTrue(sequentialLookup.feed(frame(contacts: contacts, at: 0)).isEmpty)
        XCTAssertTrue(sequentialLookup.feed(frame(contacts: [up(1, 0.4, 0.5), touch(2, 0.5, 0.5), touch(3, 0.6, 0.5)], at: 30)).isEmpty)
        XCTAssertTrue(sequentialLookup.feed(frame(contacts: [up(2, 0.5, 0.5), touch(3, 0.6, 0.5)], at: 60)).isEmpty)
        XCTAssertEqual(sequentialLookup.feed(frame(contacts: [up(3, 0.6, 0.5)], at: 100)),
                       [.command(.lookUp, repeats: 1)])

        let swipe = GestureRecognizer()
        _ = swipe.feed(frame(contacts: threeContacts(y: 0.6), at: 0))
        XCTAssertEqual(swipe.feed(frame(contacts: threeContacts(y: 0.4), at: 100)),
                       [.command(.appExpose, repeats: 1)])

        let drag = GestureRecognizer()
        let start = threeContacts(y: 0.5)
        _ = drag.feed(frame(contacts: start, at: 0))
        XCTAssertEqual(drag.feed(frame(contacts: start, at: 150)),
                       [.drag(phase: .began, dx: 0, dy: 0, sensitivityPercent: 100)])
        let moved = drag.feed(frame(contacts: threeContacts(y: 0.55), at: 200))
        guard case .drag(phase: .moved, let dx, let dy, sensitivityPercent: 100) = moved.first else {
            return XCTFail("expected a three-finger drag move")
        }
        XCTAssertEqual(dx, 0, accuracy: 0.0001)
        XCTAssertEqual(dy, 0.05, accuracy: 0.0001)
        XCTAssertEqual(drag.feed(frame(contacts: threeContacts(y: 0.55).map(release), at: 250)),
                       [.drag(phase: .ended, dx: 0, dy: 0, sensitivityPercent: 100)])
    }

    func testFourFingerWindowAndDesktopCommands() {
        XCTAssertEqual(fourFingerAction(start: fourContacts(y: 0.6), end: fourContacts(y: 0.4)), .missionControl)
        XCTAssertEqual(fourFingerAction(start: fourContacts(y: 0.4), end: fourContacts(y: 0.6)), .appExpose)
        XCTAssertEqual(fourFingerAction(start: fourContacts(x: 0.4), end: fourContacts(x: 0.6)), .spaceRight)

        let desktop = GestureRecognizer()
        _ = desktop.feed(frame(contacts: squareContacts(inset: 0.4), at: 0))
        XCTAssertEqual(desktop.feed(frame(contacts: squareContacts(inset: 0.3), at: 100)),
                       [.command(.showDesktop, repeats: 1)])

        let launcher = GestureRecognizer()
        _ = launcher.feed(frame(contacts: squareContacts(inset: 0.3), at: 0))
        XCTAssertEqual(launcher.feed(frame(contacts: squareContacts(inset: 0.4), at: 100)),
                       [.command(.appLauncher, repeats: 1)])
    }

    func testCancellationIdentifierChangeFiveFingerAndResetDoNotLeaveActions() {
        let gestures = GestureRecognizer()
        let start = threeContacts(y: 0.5)
        _ = gestures.feed(frame(contacts: start, at: 0))
        XCTAssertEqual(gestures.feed(frame(contacts: start, at: 150)),
                       [.drag(phase: .began, dx: 0, dy: 0, sensitivityPercent: 100)])
        XCTAssertEqual(gestures.reset(),
                       [.drag(phase: .ended, dx: 0, dy: 0, sensitivityPercent: 100)])

        let suppressed = GestureRecognizer()
        let five = (1...5).map { touch(UInt8($0), 0.1 * Float($0), 0.5) }
        XCTAssertTrue(suppressed.feed(frame(contacts: five, at: 0)).isEmpty)
        XCTAssertTrue(suppressed.feed(frame(contacts: [], at: 100)).isEmpty)
        XCTAssertTrue(suppressed.feed(frame(contacts: [touch(1, 0.5, 0.5)], at: 200)).isEmpty)
        XCTAssertTrue(suppressed.feed(frame(contacts: [], at: 300)).isEmpty)

        let upgrade = GestureRecognizer()
        XCTAssertTrue(upgrade.feed(frame(contacts: [touch(1, 0.5, 0.5)], at: 0)).isEmpty)
        XCTAssertTrue(upgrade.feed(frame(contacts: threeContacts(y: 0.5), at: 20)).isEmpty)
        XCTAssertEqual(upgrade.feed(frame(contacts: threeContacts(y: 0.5).map(release), at: 100)),
                       [.command(.lookUp, repeats: 1)])

        let idChange = GestureRecognizer()
        _ = idChange.feed(frame(contacts: [touch(1, 0.4, 0.4), touch(2, 0.6, 0.4)], at: 0))
        XCTAssertEqual(idChange.feed(frame(contacts: [touch(1, 0.4, 0.5), touch(2, 0.6, 0.5)], at: 100)),
                       [.scroll(vertical: 4, horizontal: 0)])
        XCTAssertTrue(idChange.feed(frame(contacts: [touch(3, 0.4, 0.5), touch(4, 0.6, 0.5)], at: 150)).isEmpty)
        XCTAssertTrue(idChange.feed(frame(contacts: [up(3, 0.4, 0.5), up(4, 0.6, 0.5)], at: 200)).isEmpty)
    }

    private func fourFingerAction(start: [TouchContact], end: [TouchContact]) -> GestureCommand {
        let gestures = GestureRecognizer()
        _ = gestures.feed(frame(contacts: start, at: 0))
        guard case .command(let command, repeats: 1) = gestures.feed(frame(contacts: end, at: 100)).first else {
            XCTFail("expected four-finger command")
            return .missionControl
        }
        return command
    }

    private func frame(contacts: [TouchContact], at milliseconds: Int64) -> TouchFrame {
        TouchFrame(type: .touch, sequence: UInt32(milliseconds),
                   timestampNanos: milliseconds * 1_000_000,
                   sensitivityPercent: 100, naturalScrolling: true, contacts: contacts)
    }

    private func touch(_ id: UInt8, _ x: Float, _ y: Float) -> TouchContact {
        TouchContact(id: id, touching: true, x: x, y: y, pressure: 0, major: 0, minor: 0)
    }

    private func up(_ id: UInt8, _ x: Float, _ y: Float) -> TouchContact {
        TouchContact(id: id, touching: false, x: x, y: y, pressure: 0, major: 0, minor: 0)
    }

    private func release(_ contact: TouchContact) -> TouchContact {
        up(contact.id, contact.x, contact.y)
    }

    private func threeContacts(y: Float) -> [TouchContact] {
        [touch(1, 0.4, y), touch(2, 0.5, y), touch(3, 0.6, y)]
    }

    private func fourContacts(x: Float = 0.5, y: Float = 0.5) -> [TouchContact] {
        [touch(1, x - 0.1, y - 0.05), touch(2, x + 0.1, y - 0.05),
         touch(3, x - 0.1, y + 0.05), touch(4, x + 0.1, y + 0.05)]
    }

    private func squareContacts(inset: Float) -> [TouchContact] {
        [touch(1, inset, inset), touch(2, 1 - inset, inset),
         touch(3, inset, 1 - inset), touch(4, 1 - inset, 1 - inset)]
    }
}
