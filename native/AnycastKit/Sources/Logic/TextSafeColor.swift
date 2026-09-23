import Foundation
import CoreGraphics

/// getTextSafeColor (utils/formatters.dart:139-153 @ 1.2.1+38) — G14. The
/// function was deleted on the Flutter line by the post-baseline visual
/// refresh but IS released behavior (lyrics tinting), so the native app
/// still implements it; the golden vendored the original.
public enum TextSafeColor {

    /// Flutter `Color.computeLuminance()`: sRGB channels linearized with the
    /// 0.03928 threshold, combined with the BT.709 weights. Alpha is
    /// irrelevant at the shipped call sites (fully opaque).
    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func luminance(argb: UInt32) -> Double {
        let red = Double((argb >> 16) & 0xFF) / 255.0
        let green = Double((argb >> 8) & 0xFF) / 255.0
        let blue = Double(argb & 0xFF) / 255.0
        return luminance(red: red, green: green, blue: blue)
    }

    /// The shipped fallback green.
    public static let fallback: UInt32 = 0xFF10_B981

    /// Below this relative luminance a color is unsafe for text on the
    /// dark lyrics background → fall back.
    public static let threshold: Double = 0.2

    public static func getTextSafeColor(argb: UInt32) -> UInt32 {
        luminance(argb: argb) < threshold ? fallback : argb
    }

    /// getBackgroundSafeColor (formatters.dart:209-219): bright colors fold
    /// onto the dark teal, others pass through. Used by the player
    /// background gradient (M3).
    public static func getBackgroundSafeColor(argb: UInt32) -> UInt32 {
        luminance(argb: argb) > 0.7 ? 0xFF11_3336 : argb
    }
}

/// Dominant-color extraction replacing palette_generator's
/// `PaletteGenerator.dominantColor` (G_palette). Golden comparison is
/// CIEDE2000 < 10, not exact equality (05 §3).
///
/// Approach: downsample, quantize each channel to 5 bits, histogram, and
/// average the winning bucket — the same shape as the Android-style
/// palette algorithm palette_generator ports.
public enum Palette {

    /// `AnycastColor.playerWarm` — the fallback when the image yields
    /// nothing.
    public static let fallback: UInt32 = 0xFF11_1316

    /// CIEDE2000 color difference (05 §3 threshold unit).
    public static func ciede2000(lhs: UInt32, rhs: UInt32) -> Double {
        let l1 = LAB(color: lhs)
        let l2 = LAB(color: rhs)

        let kL = 1.0, kC = 1.0, kH = 1.0
        let c1 = sqrt(l1.a * l1.a + l1.b * l1.b)
        let c2 = sqrt(l2.a * l2.a + l2.b * l2.b)
        let cBar = (c1 + c2) / 2

        let cBar7 = pow(cBar, 7)
        let g = 0.5 * (1 - sqrt(cBar7 / (cBar7 + pow(25.0, 7))))
        let a1Prime = l1.a * (1 + g)
        let a2Prime = l2.a * (1 + g)
        let c1Prime = sqrt(a1Prime * a1Prime + l1.b * l1.b)
        let c2Prime = sqrt(a2Prime * a2Prime + l2.b * l2.b)

        func hPrime(_ a: Double, _ b: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            var angle = atan2(b, a) * 180 / .pi
            if angle < 0 { angle += 360 }
            return angle
        }
        let h1Prime = hPrime(a1Prime, l1.b)
        let h2Prime = hPrime(a2Prime, l2.b)

        let dLPrime = l2.l - l1.l
        let dCPrime = c2Prime - c1Prime

        var dhPrime: Double
        if c1Prime * c2Prime == 0 {
            dhPrime = 0
        } else {
            dhPrime = h2Prime - h1Prime
            if dhPrime > 180 { dhPrime -= 360 }
            if dhPrime < -180 { dhPrime += 360 }
        }

        let dHPrime = 2 * sqrt(c1Prime * c2Prime) * sin(dhPrime * .pi / 360)

        let lBarPrime = (l1.l + l2.l) / 2
        let cBarPrime = (c1Prime + c2Prime) / 2

        var hBarPrime: Double
        if c1Prime * c2Prime == 0 {
            hBarPrime = h1Prime + h2Prime
        } else {
            let sum = h1Prime + h2Prime
            if abs(h1Prime - h2Prime) <= 180 {
                hBarPrime = sum / 2
            } else if sum < 360 {
                hBarPrime = (sum + 360) / 2
            } else {
                hBarPrime = (sum - 360) / 2
            }
        }

        let t = 1
            - 0.17 * cos((hBarPrime - 30) * .pi / 180)
            + 0.24 * cos(2 * hBarPrime * .pi / 180)
            + 0.32 * cos((3 * hBarPrime + 6) * .pi / 180)
            - 0.20 * cos((4 * hBarPrime - 63) * .pi / 180)

        let dTheta = 30 * exp(-pow((hBarPrime - 275) / 25, 2))
        let cBarPrime7 = pow(cBarPrime, 7)
        let rC = 2 * sqrt(cBarPrime7 / (cBarPrime7 + pow(25.0, 7)))
        let sL = 1 + (0.015 * pow(lBarPrime - 50, 2)) / sqrt(20 + pow(lBarPrime - 50, 2))
        let sC = 1 + 0.045 * cBarPrime
        let sH = 1 + 0.015 * cBarPrime * t
        let rT = -sin(2 * dTheta * .pi / 180) * rC

        let termL = dLPrime / (kL * sL)
        let termC = dCPrime / (kC * sC)
        let termH = dHPrime / (kH * sH)
        return sqrt(termL * termL + termC * termC + termH * termH + rT * termC * termH)
    }

    struct LAB {
        var l: Double
        var a: Double
        var b: Double

        init(color argb: UInt32) {
            let red = Double((argb >> 16) & 0xFF) / 255
            let green = Double((argb >> 8) & 0xFF) / 255
            let blue = Double(argb & 0xFF) / 255

            func linearize(_ c: Double) -> Double {
                c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
            }
            let x = linearize(red) * 0.4124 + linearize(green) * 0.3576 + linearize(blue) * 0.1805
            let y = linearize(red) * 0.2126 + linearize(green) * 0.7152 + linearize(blue) * 0.0722
            let z = linearize(red) * 0.0193 + linearize(green) * 0.1192 + linearize(blue) * 0.9505

            func f(_ t: Double) -> Double {
                t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116
            }
            l = 116 * f(y) - 16
            a = 500 * (f(x) - f(y))
            b = 200 * (f(y) - f(z))
        }
    }
}
