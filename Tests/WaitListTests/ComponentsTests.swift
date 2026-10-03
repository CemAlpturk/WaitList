import AppKit
import SwiftUI
import XCTest
@testable import WaitList

/// The dynamic colors in Components.swift, resolved under both appearances without any window.
final class ComponentsTests: XCTestCase {
    private struct RGB: Equatable {
        var red: Double, green: Double, blue: Double
    }

    private func rgb(_ color: Color, _ appearance: NSAppearance.Name) throws -> RGB {
        var result: RGB?
        try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            if let resolved = NSColor(color).usingColorSpace(.sRGB) {
                result = RGB(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
            }
        }
        return try XCTUnwrap(result)
    }

    private func system(_ color: NSColor, _ appearance: NSAppearance.Name) throws -> RGB {
        var result: RGB?
        try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            if let resolved = color.usingColorSpace(.sRGB) {
                result = RGB(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
            }
        }
        return try XCTUnwrap(result)
    }

    private func assertEqual(_ a: RGB, _ b: RGB, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.red, b.red, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(a.green, b.green, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(a.blue, b.blue, accuracy: 0.005, file: file, line: line)
    }

    func testSavedIsDarkerGreenInLightModeAndSystemGreenInDarkMode() throws {
        assertEqual(try rgb(.saved, .aqua), RGB(red: 0.10, green: 0.52, blue: 0.22))
        assertEqual(try rgb(.saved, .darkAqua), try system(.systemGreen, .darkAqua))
        XCTAssertNotEqual(try rgb(.saved, .aqua), try rgb(.saved, .darkAqua))
    }

    func testSpentIsDeeperBlueInLightModeAndSystemBlueInDarkMode() throws {
        assertEqual(try rgb(.spent, .aqua), RGB(red: 0.05, green: 0.40, blue: 0.85))
        assertEqual(try rgb(.spent, .darkAqua), try system(.systemBlue, .darkAqua))
        XCTAssertNotEqual(try rgb(.spent, .aqua), try rgb(.spent, .darkAqua))
    }

    func testSavedAndSpentAreDistinguishable() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            XCTAssertNotEqual(try rgb(.saved, appearance), try rgb(.spent, appearance), "\(appearance.rawValue)")
        }
    }

    func testSwiftUIResolvesTheSameColorsPerColorScheme() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        for color in [Color.saved, Color.spent] {
            let l = color.resolve(in: light)
            let d = color.resolve(in: dark)
            XCTAssertNotEqual([l.red, l.green, l.blue], [d.red, d.green, d.blue])
            XCTAssertEqual(l.opacity, 1)
            XCTAssertEqual(d.opacity, 1)
        }
    }
}
