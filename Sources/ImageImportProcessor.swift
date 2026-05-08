import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageImportResizePreset: Int, CaseIterable, Identifiable {
    case original = 0
    case max2048 = 2048
    case max1600 = 1600
    case max1280 = 1280

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .original:
            return "Original"
        case .max2048:
            return "2048 px"
        case .max1600:
            return "1600 px"
        case .max1280:
            return "1280 px"
        }
    }

    var maxPixelDimension: Int? {
        rawValue > 0 ? rawValue : nil
    }
}

struct ImageImportProcessingOptions: Equatable {
    var resizePreset: ImageImportResizePreset
    var convertsHEICToJPEG: Bool
    var jpegQuality: Double
    var anonymizesFilenames: Bool
}

struct PreparedImageImport: Equatable {
    let originalURL: URL
    let uploadURL: URL
    let wasProcessed: Bool
}

enum ImageImportProcessorError: LocalizedError {
    case unsupportedImage(String)
    case failedToCreateImage(String)
    case failedToWriteImage(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedImage(let name):
            return "Could not read \(name) as an image."
        case .failedToCreateImage(let name):
            return "Could not prepare \(name) for upload."
        case .failedToWriteImage(let name):
            return "Could not write a processed copy of \(name)."
        }
    }
}

enum ImageImportProcessor {
    private static let readableImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "webp"
    ]

    static func supportedImageFileURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            guard url.isFileURL else { return false }

            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
               type.conforms(to: .image) {
                return true
            }

            return readableImageExtensions.contains(url.pathExtension.lowercased())
        }
    }

    static func containsHEICLikeImage(in urls: [URL]) -> Bool {
        urls.contains { isHEICLike($0) }
    }

    static func prepare(
        fileURLs: [URL],
        options: ImageImportProcessingOptions
    ) async throws -> [PreparedImageImport] {
        try await Task.detached(priority: .userInitiated) {
            try prepareSynchronously(fileURLs: fileURLs, options: options)
        }.value
    }

    private static func prepareSynchronously(
        fileURLs: [URL],
        options: ImageImportProcessingOptions
    ) throws -> [PreparedImageImport] {
        let processingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WPWorkspaceImageImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: processingDirectory, withIntermediateDirectories: true)

        return try fileURLs.enumerated().map { index, url in
            try prepareImage(
                url,
                options: options,
                processingDirectory: processingDirectory,
                outputIndex: index
            )
        }
    }

    private static func prepareImage(
        _ url: URL,
        options: ImageImportProcessingOptions,
        processingDirectory: URL,
        outputIndex: Int
    ) throws -> PreparedImageImport {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageImportProcessorError.unsupportedImage(url.lastPathComponent)
        }

        let imageCount = CGImageSourceGetCount(source)
        if imageCount > 1 && url.pathExtension.lowercased() == "gif" {
            if options.anonymizesFilenames {
                return try copyImage(
                    url,
                    processingDirectory: processingDirectory,
                    outputIndex: outputIndex
                )
            }
            return PreparedImageImport(originalURL: url, uploadURL: url, wasProcessed: false)
        }

        let dimensions = pixelDimensions(for: source)
        let needsResize: Bool
        if let maxPixelDimension = options.resizePreset.maxPixelDimension {
            if let dimensions {
                needsResize = max(dimensions.width, dimensions.height) > maxPixelDimension
            } else {
                needsResize = true
            }
        } else {
            needsResize = false
        }

        let needsHEICConversion = options.convertsHEICToJPEG && isHEICLike(url)
        guard needsResize || needsHEICConversion else {
            if options.anonymizesFilenames {
                return try copyImage(
                    url,
                    processingDirectory: processingDirectory,
                    outputIndex: outputIndex
                )
            }
            return PreparedImageImport(originalURL: url, uploadURL: url, wasProcessed: false)
        }

        let outputType = outputTypeIdentifier(for: url, forceJPEG: needsHEICConversion)
        let outputURL = processedURL(
            originalURL: url,
            typeIdentifier: outputType,
            processingDirectory: processingDirectory,
            outputIndex: outputIndex,
            anonymizesFilename: options.anonymizesFilenames
        )

        let image = try createProcessedImage(
            from: source,
            originalName: url.lastPathComponent,
            maxPixelDimension: options.resizePreset.maxPixelDimension,
            dimensions: dimensions
        )

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, outputType as CFString, 1, nil) else {
            throw ImageImportProcessorError.failedToWriteImage(url.lastPathComponent)
        }

        var properties: [CFString: Any] = [:]
        if outputType == UTType.jpeg.identifier {
            properties[kCGImageDestinationLossyCompressionQuality] = max(0.1, min(1.0, options.jpegQuality))
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageImportProcessorError.failedToWriteImage(url.lastPathComponent)
        }

        return PreparedImageImport(originalURL: url, uploadURL: outputURL, wasProcessed: true)
    }

    private static func copyImage(
        _ url: URL,
        processingDirectory: URL,
        outputIndex: Int
    ) throws -> PreparedImageImport {
        let outputURL = copiedURL(
            originalURL: url,
            processingDirectory: processingDirectory,
            outputIndex: outputIndex
        )
        try FileManager.default.copyItem(at: url, to: outputURL)
        return PreparedImageImport(originalURL: url, uploadURL: outputURL, wasProcessed: true)
    }

    private static func createProcessedImage(
        from source: CGImageSource,
        originalName: String,
        maxPixelDimension: Int?,
        dimensions: (width: Int, height: Int)?
    ) throws -> CGImage {
        let fallbackMaxDimension = dimensions.map { max($0.width, $0.height) } ?? 4096
        let targetMaxDimension = maxPixelDimension ?? fallbackMaxDimension
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetMaxDimension
        ]

        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return image
        }
        if let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        throw ImageImportProcessorError.failedToCreateImage(originalName)
    }

    private static func pixelDimensions(for source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        guard let width, let height else { return nil }
        return (width, height)
    }

    private static func outputTypeIdentifier(for url: URL, forceJPEG: Bool) -> String {
        guard !forceJPEG else { return UTType.jpeg.identifier }

        switch url.pathExtension.lowercased() {
        case "png":
            return UTType.png.identifier
        case "jpg", "jpeg":
            return UTType.jpeg.identifier
        default:
            return UTType.jpeg.identifier
        }
    }

    private static func processedURL(
        originalURL: URL,
        typeIdentifier: String,
        processingDirectory: URL,
        outputIndex: Int,
        anonymizesFilename: Bool
    ) -> URL {
        let baseName = anonymizesFilename
            ? anonymizedBaseName(outputIndex: outputIndex)
            : "\(originalURL.deletingPathExtension().lastPathComponent)-\(outputIndex + 1)"
        let extensionName = typeIdentifier == UTType.png.identifier ? "png" : "jpg"
        return processingDirectory
            .appendingPathComponent(baseName)
            .appendingPathExtension(extensionName)
    }

    private static func copiedURL(
        originalURL: URL,
        processingDirectory: URL,
        outputIndex: Int
    ) -> URL {
        let extensionName = originalURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "jpg"
            : originalURL.pathExtension.lowercased()
        return processingDirectory
            .appendingPathComponent(anonymizedBaseName(outputIndex: outputIndex))
            .appendingPathExtension(extensionName)
    }

    private static func anonymizedBaseName(outputIndex: Int) -> String {
        let token = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return "img-\(String(token.prefix(20)))"
    }

    private static func isHEICLike(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "heic", "heif":
            return true
        default:
            return false
        }
    }
}
