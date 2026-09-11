import AppKit
import ISS

/// A local motion sample; never changes Spaces or needs Accessibility access.
final class AnimationCurvePreview: NSView {
  var settings = AnimationSettings() { didSet { needsDisplay = true } }
  private var timer: Timer?
  private var started = 0.0
  private var time = 0.0

  override var intrinsicContentSize: NSSize { NSSize(width: 380, height: 190) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Animation curve and motion preview")
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func playIfIdle() { if timer == nil { play() } }

  func play() {
    stop()
    time = 0
    started = ProcessInfo.processInfo.systemUptime
    let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
      guard let self else { return }
      let elapsed = ProcessInfo.processInfo.systemUptime - self.started
      self.time = self.settings.isInstant ? 1 : min(1, elapsed / self.settings.duration)
      self.needsDisplay = true
      if self.time >= 1 { self.stop() }
    }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
    needsDisplay = true
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  deinit { timer?.invalidate() }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
    let plot = NSRect(x: 36, y: 66, width: bounds.width - 54, height: bounds.height - 91)
    NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
    let grid = NSBezierPath()
    for i in 0...4 {
      let f = CGFloat(i) / 4
      grid.move(to: NSPoint(x: plot.minX + f * plot.width, y: plot.minY))
      grid.line(to: NSPoint(x: plot.minX + f * plot.width, y: plot.maxY))
      grid.move(to: NSPoint(x: plot.minX, y: plot.minY + f * plot.height))
      grid.line(to: NSPoint(x: plot.maxX, y: plot.minY + f * plot.height))
    }
    grid.lineWidth = 0.5
    grid.stroke()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor
    ]
    ("100%" as NSString).draw(at: NSPoint(x: 4, y: plot.maxY - 6), withAttributes: attributes)
    ("0%" as NSString).draw(at: NSPoint(x: 12, y: plot.minY - 5), withAttributes: attributes)
    ("Time" as NSString).draw(at: NSPoint(x: plot.midX - 12, y: plot.minY - 18), withAttributes: attributes)
    let curve = NSBezierPath()
    for i in 0...160 {
      let t = Double(i) / 160
      let p = settings.isInstant ? (i == 0 ? 0 : 1) : iss_animation_progress(t, settings.easeIn, settings.easeOut)
      let point = NSPoint(x: plot.minX + t * plot.width, y: plot.minY + p * plot.height)
      if i == 0 { curve.move(to: point) } else { curve.line(to: point) }
    }
    NSColor.controlAccentColor.setStroke()
    curve.lineWidth = 2.5
    curve.stroke()

    let progress = settings.isInstant ? time : iss_animation_progress(time, settings.easeIn, settings.easeOut)
    let dot = NSRect(x: plot.minX + time * plot.width - 4, y: plot.minY + progress * plot.height - 4, width: 8, height: 8)
    NSColor.controlAccentColor.setFill()
    NSBezierPath(ovalIn: dot).fill()
    let track = NSRect(x: 18, y: 14, width: bounds.width - 36, height: 28)
    NSColor.quaternaryLabelColor.setFill()
    NSBezierPath(roundedRect: track, xRadius: 6, yRadius: 6).fill()
    let card = NSRect(x: track.minX + progress * (track.width - 42), y: track.minY + 3, width: 42, height: 22)
    NSColor.controlAccentColor.setFill()
    NSBezierPath(roundedRect: card, xRadius: 4, yRadius: 4).fill()
  }
}
