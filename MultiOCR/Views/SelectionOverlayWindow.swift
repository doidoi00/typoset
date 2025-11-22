//
//  SelectionOverlayWindow.swift
//  MultiOCR
//
//  Full-screen overlay for area selection with crosshair
//

import Cocoa

class SelectionOverlayWindow: NSWindow {
    private var selectionView: SelectionView
    private var completionHandler: ((CGRect) -> Void)?
    
    init(screen: NSScreen, completion: @escaping (CGRect) -> Void) {
        self.completionHandler = completion
        self.selectionView = SelectionView()
        
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        
        self.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        self.isOpaque = false
        // Use a high level but not screenSaver to avoid locking the system completely if something goes wrong
        self.level = .modalPanel
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.hidesOnDeactivate = false
        
        selectionView.frame = screen.frame
        selectionView.onSelectionComplete = { [weak self] rect in
            self?.completionHandler?(rect)
            self?.close()
        }
        
        self.contentView = selectionView
        
        // Set cursor to crosshair
        NSCursor.crosshair.set()
        
        // Ensure we become key window to receive events
        self.makeKeyAndOrderFront(nil)
        self.makeFirstResponder(selectionView)
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // Ensure we catch Escape key even if focus is somehow lost or handled differently
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape key
            self.close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func close() {
        NSCursor.arrow.set()
        super.close()
    }
}

class SelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isDragging = false
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()
        
        // Draw "Press Esc to cancel" instruction
        drawInstructionText()
        
        // Draw selection rectangle if dragging
        if isDragging, let start = startPoint, let current = currentPoint {
            let selectionRect = rectFromPoints(start, current)
            
            // Clear the selected area
            NSColor.clear.setFill()
            selectionRect.fill(using: .copy)
            
            // Draw border
            NSColor.systemBlue.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 2.0
            borderPath.stroke()
            
            // Draw dimensions label
            drawDimensionsLabel(for: selectionRect)
        }
    }
    
    private func drawInstructionText() {
        let text = "Click and drag to capture area (Press Esc to cancel)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
            .shadow: NSShadow()
        ]
        
        if let shadow = attributes[.shadow] as? NSShadow {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
        }
        
        let textSize = text.size(withAttributes: attributes)
        let screenRect = self.bounds
        
        // Draw at top center
        let point = NSPoint(
            x: screenRect.midX - textSize.width / 2,
            y: screenRect.maxY - textSize.height - 50
        )
        
        text.draw(at: point, withAttributes: attributes)
    }
    
    private func drawDimensionsLabel(for rect: NSRect) {
        let width = Int(rect.width)
        let height = Int(rect.height)
        let dimensionText = "\(width) × \(height)"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        
        let textSize = dimensionText.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width + 8,
            height: textSize.height + 4
        )
        
        NSColor.black.withAlphaComponent(0.7).setFill()
        textRect.fill()
        
        dimensionText.draw(
            at: NSPoint(x: textRect.minX + 4, y: textRect.minY + 2),
            withAttributes: attributes
        )
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        isDragging = true
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint, let end = currentPoint else { return }
        
        isDragging = false
        let selectionRect = rectFromPoints(start, end)
        
        // Only complete if selection is large enough
        if selectionRect.width > 10 && selectionRect.height > 10 {
            // Convert to screen coordinates
            if let screen = window?.screen {
                let screenRect = CGRect(
                    x: selectionRect.origin.x,
                    y: screen.frame.height - selectionRect.origin.y - selectionRect.height,
                    width: selectionRect.width,
                    height: selectionRect.height
                )
                onSelectionComplete?(screenRect)
            }
        }
        
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }
    
    override func keyDown(with event: NSEvent) {
        // Cancel selection on Escape
        if event.keyCode == 53 { // Escape key
            window?.close()
        }
    }
    
    private func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
}
