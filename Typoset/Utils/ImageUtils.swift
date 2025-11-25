import AppKit

class ImageUtils {
    static func resizeImage(_ image: NSImage, level: String) -> NSImage {
        let maxDimension: CGFloat
        switch level {
        case "Original":
            return image
        case "High":
            maxDimension = 2048
        case "Low":
            maxDimension = 768
        case "Medium":
            fallthrough
        default:
            maxDimension = 1024
        }
        
        let size = image.size
        // Handle potential zero size to avoid division by zero
        if size.width == 0 || size.height == 0 { return image }
        
        let aspectRatio = size.width / size.height
        
        var newSize: NSSize
        if size.width > size.height {
            if size.width <= maxDimension { return image }
            newSize = NSSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            if size.height <= maxDimension { return image }
            newSize = NSSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        
        return newImage
    }
}
