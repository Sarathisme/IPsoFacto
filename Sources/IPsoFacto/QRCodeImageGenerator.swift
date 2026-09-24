import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders a scannable QR code NSImage from a short ASCII payload (an
/// IPv4 address), via Core Image's built-in generator. AppKit/Core Image
/// glue -- not unit tested; see the manual QA checklist in the plan.
enum QRCodeImageGenerator {
    /// Shared across calls: CIContext construction sets up GPU-backed
    /// resources and is comparatively expensive, but this function runs on
    /// every menu open (menuWillOpen -> rebuildMenu -> makeQRCodeMenuItem),
    /// not just on network change -- reusing one context avoids repeating
    /// that cost on every dropdown open.
    private static let context = CIContext()

    /// Returns an opaque `sizePoints` x `sizePoints` image: black
    /// modules on a solid white background. Always black-on-white,
    /// never tinted or made a template image, regardless of
    /// Light/Dark Mode (Decision #2). Returns nil if Core Image cannot
    /// render the payload (not expected for a short IPv4 string).
    static func image(forPayload payload: String, sizePoints: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard let qrImage = filter.outputImage else { return nil }

        let whiteBackground = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: qrImage.extent)
        let composited = qrImage.composited(over: whiteBackground)

        // Nearest-neighbor scaling: the default smooth interpolation blurs
        // QR module edges into gray, which reduces the contrast a phone
        // camera relies on to decode the code. Sharp, unblended
        // black/white pixels keep the code reliably scannable at any size.
        let scale = sizePoints / composited.extent.width
        let scaled = composited.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: sizePoints, height: sizePoints))
    }
}
