import SwiftUI

struct OverlayView: View {
    let onSelect: (CGRect) -> Void
    let onCancel: () -> Void
    
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    
    var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if startPoint == nil {
                                startPoint = value.startLocation
                            }
                            currentPoint = value.location
                        }
                        .onEnded { value in
                            if let rect = selectionRect, rect.width > 5, rect.height > 5 {
                                onSelect(rect)
                            } else {
                                // Click without drag or too small
                                onCancel()
                            }
                            startPoint = nil
                            currentPoint = nil
                        }
                )
            
            if let rect = selectionRect {
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .background(Color.clear)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .cursor(.crosshair)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { _ in
            cursor.push()
        }
    }
}
