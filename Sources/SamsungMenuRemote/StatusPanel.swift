import AppKit
import SwiftUI

extension Notification.Name {
    static let remotePanelDidOpen = Notification.Name("RemotePanelDidOpen")
}

/// Menu bar item with a borderless, rounded panel that resizes from its top edge.
/// MenuBarExtra's window has fixed square-ish corners and jumps when its content changes height.
@MainActor final class StatusPanel: NSObject, NSWindowDelegate {
    static let cornerRadius: CGFloat = 28
    let panel: RemoteWindow
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var closedAt = Date.distantPast

    init(remote: Remote) {
        panel = RemoteWindow()
        super.init()
        let host = FittingHostingView(rootView: RemotePanel(remote: remote))
        host.onResize = { [weak self] in self?.fit(animated: true) }
        panel.install(host)
        panel.delegate = self
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "appletvremote.gen1", accessibilityDescription: "Samsung Menu Remote")
            button.target = self
            button.action = #selector(toggle)
        }
    }

    @objc private func toggle() {
        if panel.isVisible { close(); return }
        // The click that dismissed the panel by resigning key must not reopen it.
        guard Date().timeIntervalSince(closedAt) > 0.3 else { return }
        show()
    }

    func show() {
        fit(animated: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        item.button?.highlight(true)
        NotificationCenter.default.post(name: .remotePanelDidOpen, object: nil)
    }

    func close() {
        closedAt = Date()
        item.button?.highlight(false)
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func fit(animated: Bool) {
        guard let host = panel.host else { return }
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = NSRect(origin: .zero, size: size)
        if let button = item.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            frame.origin.x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
            frame.origin.y = anchor.minY - 6 - size.height
        } else {
            frame.origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - size.height)
        }
        guard frame != panel.frame else { return }
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}

final class RemoteWindow: NSPanel {
    private(set) var host: NSView?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 312, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    func install(_ host: NSView) {
        let radius = StatusPanel.cornerRadius
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.mask(radius: radius)

        let edge = EdgeView()
        edge.wantsLayer = true
        edge.layer?.cornerRadius = radius
        edge.layer?.cornerCurve = .continuous
        edge.layer?.borderWidth = 0.5
        edge.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        for view in [host, edge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                view.topAnchor.constraint(equalTo: background.topAnchor),
                view.bottomAnchor.constraint(equalTo: background.bottomAnchor)
            ])
        }
        contentView = background
        self.host = host
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        invalidateShadow()
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let length = radius * 2 + 1
        let image = NSImage(size: NSSize(width: length, height: length), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Hairline border drawn above the content; it never takes clicks.
    private final class EdgeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Reports SwiftUI size changes so the panel can follow its content.
final class FittingHostingView<Content: View>: NSHostingView<Content> {
    var onResize: (() -> Void)?
    private var pending = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            self?.pending = false
            self?.onResize?()
        }
    }
}
