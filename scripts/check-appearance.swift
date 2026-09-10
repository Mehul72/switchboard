import AppKit
import SwiftUI

private struct RGBA {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            fatalError("Cannot resolve \(color) in sRGB")
        }
        red = Double(rgb.redComponent)
        green = Double(rgb.greenComponent)
        blue = Double(rgb.blueComponent)
        alpha = Double(rgb.alphaComponent)
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    func over(_ background: RGBA) -> RGBA {
        let opacity = alpha + background.alpha * (1 - alpha)
        guard opacity > 0 else { return self }
        func blend(_ foreground: Double, _ back: Double) -> Double {
            (foreground * alpha + back * background.alpha * (1 - alpha)) / opacity
        }
        return RGBA(red: blend(red, background.red), green: blend(green, background.green),
                    blue: blend(blue, background.blue), alpha: opacity)
    }

    private var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(against background: RGBA) -> Double {
        let foregroundLuminance = over(background).luminance
        let backgroundLuminance = background.luminance
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }
}

@main
private struct AppearanceChecks {
    static func main() {
        let appearances: [(String, NSAppearance.Name)] = [
            ("Light", .aqua), ("Dark", .darkAqua),
            ("Light high contrast", .accessibilityHighContrastAqua),
            ("Dark high contrast", .accessibilityHighContrastDarkAqua)
        ]
        let backdrops = [("white", RGBA(.white)), ("black", RGBA(.black))]
        var failures: [String] = []
        var checks = 0
        var minimumTextRatio = Double.infinity
        var skippedAppearances: [String] = []

        func require(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { failures.append(message) }
        }

        for (appearanceLabel, appearanceName) in appearances {
            guard let appearance = NSAppearance(named: appearanceName) else {
                fatalError("Missing appearance: \(appearanceName)")
            }
            // AppKit normalizes high-contrast names unless Increase Contrast is enabled.
            guard appearance.name == appearanceName else {
                skippedAppearances.append(appearanceLabel)
                continue
            }
            appearance.performAsCurrentDrawingAppearance {
                func resolve(_ color: Color) -> RGBA { RGBA(NSColor(color)) }
                let textColors = [("primary", Theme.primary), ("secondary", Theme.secondary),
                                  ("tertiary", Theme.tertiary), ("accent", Theme.accent)]
                let surfaces = [("canvas", Theme.canvas), ("card", Theme.groupBackground),
                                ("field", Theme.fieldBackground), ("control", Theme.controlBackground)]

                for (surfaceLabel, surfaceColor) in surfaces {
                    let surface = resolve(surfaceColor)
                    require(surface.alpha >= 0.999,
                            "\(appearanceLabel): \(surfaceLabel) must be opaque (alpha \(surface.alpha))")
                    for (backdropLabel, backdrop) in backdrops {
                        let background = surface.over(backdrop)
                        for (textLabel, textColor) in textColors {
                            let ratio = resolve(textColor).contrast(against: background)
                            minimumTextRatio = min(minimumTextRatio, ratio)
                            require(ratio >= 4.5,
                                    String(format: "%@: %@ on %@ over %@ is %.2f:1, requires 4.5:1",
                                           appearanceLabel, textLabel, surfaceLabel, backdropLabel, ratio))
                        }
                    }
                }

                let selection = resolve(Theme.selectionBackground)
                require(selection.alpha >= 0.999,
                        "\(appearanceLabel): selection background must be opaque")
                let selectionRatio = resolve(Theme.selectionForeground).contrast(against: selection)
                minimumTextRatio = min(minimumTextRatio, selectionRatio)
                require(selectionRatio >= 4.5,
                        String(format: "%@: selected text is %.2f:1, requires 4.5:1",
                               appearanceLabel, selectionRatio))
                let focusRatio = resolve(Theme.accent).contrast(against: resolve(Theme.canvas))
                require(focusRatio >= 3,
                        String(format: "%@: focus indicator is %.2f:1, requires 3:1",
                               appearanceLabel, focusRatio))
            }
        }

        for failure in failures { print("FAIL: \(failure)") }
        for appearance in skippedAppearances {
            print("SKIP: \(appearance) is unavailable in the current macOS accessibility settings.")
        }
        print(String(format: "%d appearance checks, %d failures. Lowest text contrast: %.2f:1.",
                     checks, failures.count, minimumTextRatio))
        if !failures.isEmpty { exit(1) }
    }
}
