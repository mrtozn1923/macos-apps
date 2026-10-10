import CoreGraphics
import Vision

enum TextRecognizer {
    /// Recognizes text in reading order; lines are joined with newlines.
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request: VNRecognizeTextRequest = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let supported: [String] = (try? request.supportedRecognitionLanguages()) ?? []
            request.recognitionLanguages = ["tr-TR", "en-US"].filter { supported.contains($0) }

            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let observations: [VNRecognizedTextObservation] = request.results ?? []
            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
