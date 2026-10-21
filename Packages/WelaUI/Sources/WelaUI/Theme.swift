import SwiftUI

#if !os(macOS)
  import UIKit
  typealias PlatformColor = UIColor
#else
  import AppKit
  typealias PlatformColor = NSColor
#endif

extension PlatformColor {
  convenience init(hex: UInt32, alpha: CGFloat = 1) {
    #if !os(macOS)
      self.init(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    #else
      self.init(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    #endif
  }

  static func fromHexString(_ string: String) -> PlatformColor? {
    let s = string.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return PlatformColor(hex: v)
  }

  /// The colour in sRGB, so hue/saturation and RGB components can be read.
  var srgb: PlatformColor? {
    #if !os(macOS)
      return self
    #else
      return usingColorSpace(.sRGB)
    #endif
  }
}

extension Color {
  /// Colour that follows the system appearance (Paper / Night Paper).
  init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
    #if !os(macOS)
      self.init(
        uiColor: UIColor { traits in
          traits.userInterfaceStyle == .dark
            ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        })
    #else
      self.init(
        nsColor: NSColor(
          name: nil,
          dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
              ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
          }))
    #endif
  }

  init(platformColor: PlatformColor) {
    #if !os(macOS)
      self.init(uiColor: platformColor)
    #else
      self.init(nsColor: platformColor)
    #endif
  }
}

/// Paper theme tokens (see the implementation plan, section 5).
public enum Theme {
  public static let page = Color(light: 0xF7F2E8, dark: 0x1F1D1A)
  public static let rule = Color(light: 0xDDD3C0, dark: 0x3A362F)
  public static let field = Color(light: 0xEEE6D6, dark: 0x2A2722)
  public static let ink = Color(light: 0x2B2925, dark: 0xECE6D9)
  public static let softInk = Color(light: 0x6F685C, dark: 0xA39B8C)
  /// Decorative only; never for text users must read.
  public static let pencil = Color(light: 0xA9A192, dark: 0x6E685D)
  public static let redPen = Color(light: 0xB8402C, dark: 0xE0715C)
  public static let highlighter = Color(
    light: 0xF3DF8E, dark: 0x5A4E22, lightAlpha: 0.55, darkAlpha: 0.6)
  public static let blueInk = Color(light: 0x3D5A96, dark: 0x8FA8DE)
  public static let greenInk = Color(light: 0x5F8A5E, dark: 0x93BE8F)
  public static let plumInk = Color(light: 0x7B5486, dark: 0xB994C4)
  public static let ochre = Color(light: 0xBF8A2C, dark: 0xDDB15E)
  /// The "now" card: page lightened about 70% (light) / the field tone (dark).
  public static let card = Color(light: 0xFDFBF6, dark: 0x2A2722)
  /// Text on a filled blueInk pill.
  public static let onBlue = Color(light: 0xFFFFFF, dark: 0x14213D)

  /// Calendar colour for dots and status marks. User-picked colours are desaturated by ~15%.
  public static func calendarColor(hex: String, desaturate: Bool = false) -> Color {
    guard let c = PlatformColor.fromHexString(hex)?.srgb else { return softInk }
    guard desaturate else { return Color(platformColor: c) }
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return Color(
      platformColor: PlatformColor(hue: h, saturation: s * 0.85, brightness: b, alpha: a))
  }
}

extension Color {
  /// "#RRGGBB" for a colour (used to store user colour overrides).
  var hexString: String {
    let c = PlatformColor(self).srgb ?? PlatformColor(hex: 0x808080)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(
      format: "#%02X%02X%02X", Int((min(max(r, 0), 1) * 255).rounded()),
      Int((min(max(g, 0), 1) * 255).rounded()), Int((min(max(b, 0), 1) * 255).rounded()))
  }
}

// MARK: Text size

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }

extension EnvironmentValues {
  /// Small 0.9, Default 1, Large 1.15.
  public var welaTextScale: CGFloat {
    get { self[TextScaleKey.self] }
    set { self[TextScaleKey.self] = newValue }
  }
}

struct WelaFont: ViewModifier {
  @Environment(\.welaTextScale) private var scale
  let size: CGFloat
  let weight: Font.Weight
  let serif: Bool

  func body(content: Content) -> some View {
    content.font(.system(size: size * scale, weight: weight, design: serif ? .serif : .default))
  }
}

extension View {
  func welaFont(_ size: CGFloat, weight: Font.Weight = .regular, serif: Bool = false) -> some View {
    modifier(WelaFont(size: size, weight: weight, serif: serif))
  }
}

/// 150 ms ease-out, or nothing when Reduce Motion is on.
struct WelaAnimation {
  static func standard(reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: 0.15)
  }
}

extension View {
  /// A bare icon or pill menu: borderless on the Mac, a plain button on iOS.
  func welaMenuStyle() -> some View {
    #if os(macOS)
      self.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    #else
      self.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    #endif
  }
}
