import AppKit

/// Menu bar icon: a calendar glyph with today's day number.
final class StatusItemController {
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var onClick: (() -> Void)?
  private var observers: [NSObjectProtocol] = []

  var button: NSStatusBarButton? { statusItem.button }

  init() {
    button?.target = self
    button?.action = #selector(clicked)
    button?.setAccessibilityLabel("Wela Calendar")
    refresh()
    let center = NotificationCenter.default
    for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          self?.refresh()
        })
    }
  }

  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  @objc private func clicked() { onClick?() }

  func refresh() {
    let day = Calendar.current.component(.day, from: Date())
    button?.image = Self.icon(day: day)
    button?.setAccessibilityValue("Today is the \(day)")
  }

  static func icon(day: Int) -> NSImage {
    let size = NSSize(width: 20, height: 16)
    let image = NSImage(size: size, flipped: false) { rect in
      let body = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
      body.lineWidth = 1.3
      NSColor.black.setStroke()
      body.stroke()
      let text = "\(day)" as NSString
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor.black,
      ]
      let textSize = text.size(withAttributes: attributes)
      text.draw(
        at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
        withAttributes: attributes)
      return true
    }
    image.isTemplate = true
    return image
  }
}
