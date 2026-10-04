import AppKit
import ROACore
import ROAMac

final class DiagnosticsWindow: NSObject {
    private var window: NSWindow?
    private var text: NSTextView?
    private var report = ""

    func show(status: ServiceStatus?) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "ROA — Status & Diagnostics"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 360, height: 220)
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 64, width: 440, height: 276))
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.autoresizingMask = [.width]
            text.string = report
            scroll.documentView = text
            window.contentView?.addSubview(scroll)
            let copy = NSButton(title: "Copy Diagnostics", target: self, action: #selector(copyReport))
            copy.frame = NSRect(x: 20, y: 18, width: 170, height: 32)
            window.contentView?.addSubview(copy)
            window.center()
            self.window = window
            self.text = text
        }
        update(status: status)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(status: ServiceStatus?) {
        let updated = SessionPresentation.diagnostics(status)
        guard updated != report else { return }
        report = updated
        let selection = text?.selectedRange()
        let scroll = text?.enclosingScrollView
        let origin = scroll?.contentView.bounds.origin
        text?.string = report
        if let selection, NSMaxRange(selection) <= report.utf16.count {
            text?.setSelectedRange(selection)
        }
        if let origin, let scroll {
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    @objc private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
