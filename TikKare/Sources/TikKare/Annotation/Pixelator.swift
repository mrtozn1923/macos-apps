import CoreImage
import CoreImage.CIFilterBuiltins

enum Pixelator {
    private static let context: CIContext = CIContext(options: [.useSoftwareRenderer: false])

    static func pixelate(_ image: CGImage, blockSize: CGFloat) -> CGImage? {
        let input: CIImage = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(max(blockSize, 4))
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return context.createCGImage(output, from: input.extent)
    }
}
