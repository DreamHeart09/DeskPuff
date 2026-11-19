import AppKit
import Foundation

/// Data-only appearance presets. Add a catalog entry to create another package
/// look; the shared box renderer continues to provide the physical behavior.
struct CigaretteBoxStyle: Identifiable {
    let id: String
    let name: String
    let brand: String
    let subtitle: String
    let body: [NSColor]
    let lid: [NSColor]
    let foil: NSColor
    let edge: NSColor
    let fold: NSColor
    var previewArtwork: NSImage? = nil
    /// A complete, flat front-face print for the standard hard-pack template.
    /// The shared renderer maps its upper band to the moving lid and keeps
    /// legacy multi-face artwork available for higher fidelity packages.
    var frontArtwork: NSImage? = nil
    var bodyArtwork: NSImage? = nil
    var scaledBodyArtwork: NSImage? = nil
    var lidOutsideArtwork: NSImage? = nil
    var lidOutsideOpenArtwork: NSImage? = nil
    var geometry: CigaretteBoxGeometry = .standard

    var cigaretteStyleID: String? = nil

    static let builtIns: [CigaretteBoxStyle] = [
        CigaretteBoxStyle(id: "zhonghua-fallback", name: "中华·经典硬盒", brand: "中华", subtitle: "CHUNGHWA · CLASSIC",
                          body: [c(0.76, 0.035, 0.075), c(0.43, 0.015, 0.035), c(0.66, 0.025, 0.055)],
                          lid: [c(0.76, 0.035, 0.075), c(0.50, 0.018, 0.035)],
                          foil: c(0.91, 0.75, 0.42), edge: c(0.78, 0.60, 0.30),
                          fold: NSColor(calibratedWhite: 1, alpha: 0.12),
                          cigaretteStyleID: "cigarette-zhonghua-classic")
    ]

    static let `default` = builtIns[0]

    /// Retired palettes remain available as color-only package bases without
    /// registering the old fictional brands as selectable presets.
    private static let retiredPaletteBases: [String: CigaretteBoxStyle] = [
        "yunlan-red": CigaretteBoxStyle(id: "yunlan-red", name: "Retired palette", brand: "", subtitle: "",
            body: [c(0.64, 0.055, 0.09), c(0.47, 0.028, 0.062), c(0.58, 0.045, 0.078)],
            lid: [c(0.65, 0.055, 0.09), c(0.48, 0.028, 0.06)],
            foil: c(0.92, 0.76, 0.49), edge: c(0.82, 0.62, 0.31), fold: NSColor(calibratedWhite: 1, alpha: 0.12)),
        "jade-green": CigaretteBoxStyle(id: "jade-green", name: "Retired palette", brand: "", subtitle: "",
            body: [c(0.12, 0.38, 0.30), c(0.045, 0.22, 0.19), c(0.08, 0.31, 0.25)],
            lid: [c(0.15, 0.40, 0.31), c(0.055, 0.22, 0.19)],
            foil: c(0.86, 0.78, 0.52), edge: c(0.73, 0.70, 0.43), fold: NSColor(calibratedWhite: 1, alpha: 0.14)),
        "midnight-blue": CigaretteBoxStyle(id: "midnight-blue", name: "Retired palette", brand: "", subtitle: "",
            body: [c(0.18, 0.30, 0.48), c(0.08, 0.16, 0.31), c(0.13, 0.24, 0.40)],
            lid: [c(0.20, 0.32, 0.50), c(0.08, 0.16, 0.29)],
            foil: c(0.77, 0.85, 0.88), edge: c(0.62, 0.76, 0.84), fold: NSColor(calibratedWhite: 1, alpha: 0.15))
    ]

    static func paletteBase(_ id: String?) -> CigaretteBoxStyle {
        guard let id else { return .default }
        return builtIns.first { $0.id == id } ?? retiredPaletteBases[id] ?? .default
    }

    static func migratedPresetID(_ id: String) -> String {
        switch id {
        case "zhonghua-fallback", "user:zhonghua-fallback",
             "yunlan-red", "jade-green", "midnight-blue",
             "user:yunlan-red", "user:jade-green", "user:midnight-blue":
            return "user:zhonghua-classic"
        default: return id
        }
    }
}

/// Reusable carton geometry shared by hard-pack families. Artwork and the
/// mechanical layout are separate so a brand package does not need code.
struct CigaretteBoxGeometry {
    var type: String = "standard-hard"
    var lidBandFraction: CGFloat = 25.0 / 86.0
    var frontAspectRatio: CGFloat? = nil
    var rowCounts: [Int] = [7, 6, 7]
    var cigaretteCount: Int = 20
    var cigaretteDiameterMM: CGFloat? = nil

    static let standard = CigaretteBoxGeometry()
    var isSlimHard: Bool { type == "slim-hard" }
    var isTwoRow: Bool { rowCounts.count == 2 }
}

/// Data-only finish and flame palette for the shared 2D lighter renderer.
struct LighterStyle: Identifiable {
    let id: String
    let name: String
    let body: [NSColor]
    let metal: [NSColor]
    let flame: [NSColor]
    var artwork: NSImage? = nil
    var previewArtwork: NSImage? = nil
    var artworkFrame: NSRect? = nil
    /// Normalized source rect in AppKit's lower-left image coordinates.
    var artworkSourceRect: CGRect? = nil

    static let builtIns: [LighterStyle] = {
        func photoStyle(id: String, name: String, resource: String, body: [NSColor], flame: [NSColor]) -> LighterStyle {
            let artwork = Bundle.module.url(forResource: resource, withExtension: "png", subdirectory: "Resources")
                .flatMap(NSImage.init(contentsOf:))
            artwork?.size = NSSize(width: 1024, height: 1536)
            let frame = artwork == nil ? nil : NSRect(x: 73, y: 13, width: 64, height: 222)
            let source = artwork == nil ? nil : CGRect(x: 305.0 / 1024, y: 40.0 / 1536,
                                                        width: 460.0 / 1024, height: 1460.0 / 1536)
            return LighterStyle(id: id, name: name, body: body,
                                metal: [c(0.88, 0.89, 0.87), c(0.50, 0.53, 0.55)], flame: flame,
                                artwork: artwork, previewArtwork: artwork,
                                artworkFrame: frame, artworkSourceRect: source)
        }
        return [
            photoStyle(id: "silver-flint", name: "琥珀·经典橙", resource: "LighterAmberPhoto",
                       body: [c(0.98, 0.42, 0.055), c(0.52, 0.16, 0.018), c(1, 0.65, 0.16)],
                       flame: [c(1, 0.37, 0.06), c(1, 0.78, 0.20), c(1, 0.96, 0.74)]),
            photoStyle(id: "crystal-clear", name: "冰透·无色透明", resource: "LighterCrystalClear",
                       body: [c(0.86, 0.92, 0.96), c(0.45, 0.55, 0.62), c(0.98, 0.99, 1)],
                       flame: [c(1, 0.37, 0.06), c(1, 0.78, 0.20), c(1, 0.96, 0.74)]),
            photoStyle(id: "ruby-red", name: "樱桃·经典红", resource: "LighterRubyRed",
                       body: [c(0.84, 0.10, 0.13), c(0.38, 0.025, 0.04), c(1, 0.34, 0.28)],
                       flame: [c(1, 0.34, 0.04), c(1, 0.70, 0.14), c(1, 0.96, 0.70)]),
            photoStyle(id: "cobalt-blue", name: "钴蓝·经典蓝", resource: "LighterCobaltBlue",
                       body: [c(0.08, 0.31, 0.84), c(0.015, 0.075, 0.38), c(0.30, 0.60, 1)],
                       flame: [c(1, 0.34, 0.04), c(1, 0.70, 0.14), c(1, 0.96, 0.70)]),
            photoStyle(id: "emerald-green", name: "翡翠·经典绿", resource: "LighterEmeraldGreen",
                       body: [c(0.05, 0.58, 0.30), c(0.012, 0.23, 0.11), c(0.28, 0.88, 0.50)],
                       flame: [c(1, 0.34, 0.04), c(1, 0.70, 0.14), c(1, 0.96, 0.70)])
        ]
    }()
    static let `default` = builtIns[0]
}

/// Material and trim palette for the common 2D ashtray renderer.
struct AshtrayStyle: Identifiable {
    let id: String
    let name: String
    let body: [NSColor]
    let rim: [NSColor]
    let basin: [NSColor]
    let trim: NSColor
    let bodyStroke: NSColor
    let highlight: NSColor
    let handleFill: NSColor
    let handleStroke: NSColor
    let handleGlyph: NSColor
    var artwork: NSImage? = nil
    var basinFrame: NSRect? = nil
    var previewArtwork: NSImage? = nil

    var artworkFrame: NSRect? = nil

    static let builtIns: [AshtrayStyle] = {
        let glassArtwork = Bundle.module.resourceURL
            .map { $0.appendingPathComponent("Resources/AshtrayGlass.png") }
            .flatMap(NSImage.init(contentsOf:))
        let glass = AshtrayStyle(id: "clear-glass", name: "清透·厚底玻璃",
                             body: [c(0.84, 0.90, 0.92), c(0.58, 0.67, 0.70), c(0.78, 0.85, 0.87)],
                             rim: [c(0.96, 0.98, 1), c(0.56, 0.66, 0.70)],
                             basin: [c(0.60, 0.70, 0.73), c(0.38, 0.48, 0.52), c(0.76, 0.83, 0.85)],
                             trim: c(0.73, 0.82, 0.85), bodyStroke: c(0.42, 0.53, 0.57),
                             highlight: c(1, 1, 1), handleFill: c(0.90, 0.95, 0.96),
                             handleStroke: c(0.52, 0.63, 0.66), handleGlyph: NSColor(calibratedWhite: 0.2, alpha: 1),
                             artwork: glassArtwork, basinFrame: NSRect(x: 42, y: 65, width: 236, height: 96),
                             previewArtwork: glassArtwork)
        return [
            glass,
            photoStyle(id: "white-ceramic", name: "素白釉陶瓷", height: 188,
                       basin: NSRect(x: 55, y: 63, width: 210, height: 84), palette: glass),
            photoStyle(id: "brushed-steel", name: "拉丝不锈钢", height: 186,
                       basin: NSRect(x: 53, y: 63, width: 214, height: 83), palette: glass),
            photoStyle(id: "black-marble", name: "曜黑大理石", height: 195,
                       basin: NSRect(x: 53, y: 64, width: 216, height: 88), palette: glass),
            photoStyle(id: "solid-gold", name: "纯金典藏", height: 186,
                       basin: NSRect(x: 55, y: 62, width: 214, height: 83), palette: glass)
        ]
    }()

    private static func photoStyle(id: String, name: String, height: CGFloat,
                                   basin: NSRect, palette: AshtrayStyle) -> AshtrayStyle {
        let artwork = Bundle.module.url(forResource: id, withExtension: "png", subdirectory: "Resources/Ashtrays")
            .flatMap(NSImage.init(contentsOf:))
        return AshtrayStyle(id: id, name: name, body: palette.body, rim: palette.rim, basin: palette.basin,
                            trim: palette.trim, bodyStroke: palette.bodyStroke, highlight: palette.highlight,
                            handleFill: palette.handleFill, handleStroke: palette.handleStroke,
                            handleGlyph: palette.handleGlyph, artwork: artwork, basinFrame: basin,
                            previewArtwork: artwork, artworkFrame: artwork.map { _ in
                                NSRect(x: 16, y: 20, width: 288, height: height)
                            })
    }

    static let `default` = builtIns[0]
}

private func c(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

@MainActor final class StylePackageRegistry {
    static let shared = StylePackageRegistry()

    private(set) var cigaretteBoxes = CigaretteBoxStyle.builtIns
    private(set) var ashtrays = AshtrayStyle.builtIns
    private(set) var lighters = LighterStyle.builtIns

    /// User-facing presets exclude the fallback rendering style and retired
    /// fictional presets. The fixed ordering keeps Zhonghua first and follows
    /// the requested target catalog regardless of directory enumeration order.
    var visibleCigaretteBoxes: [CigaretteBoxStyle] {
        let hiddenIDs: Set<String> = ["zhonghua-fallback", "yunlan-red", "jade-green", "midnight-blue",
                                      "user:yunlan-red", "user:jade-green", "user:midnight-blue"]
        let targetOrder = [
            "user:zhonghua-classic", "user:baisha-hard", "user:hongtashan-classic1956",
            "user:liqun-new", "user:shuangxi-classic1906", "user:xuanhemen-slim",
            "user:furongwang-hard", "user:diamond-lotus-hard", "user:yuxi-hard-harmony",
            "user:huanghelou-hard1916-ruyi", "user:goldenleaf-tianye"
        ]
        let positions = Dictionary(uniqueKeysWithValues: targetOrder.enumerated().map { ($1, $0) })
        return cigaretteBoxes.filter { !hiddenIDs.contains($0.id) }.sorted {
            let first = positions[$0.id] ?? targetOrder.count
            let second = positions[$1.id] ?? targetOrder.count
            return first == second ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : first < second
        }
    }
    private(set) var diagnostics: [String] = []

    private let fileManager = FileManager.default
    private let maxPackagesPerKind = 100
    private let maxManifestBytes = 1_048_576
    private let maxImageBytes = 16 * 1_048_576
    private let maxPackageBytes = 64 * 1_048_576
    private let maxTotalPackageBytes = 256 * 1_048_576
    private let maxImageDimension = 4096
    private var totalPackageBytes = 0

    private func logDiagnostic(_ message: String) {
        diagnostics.append(message)
        NSLog("[DeskPuff Styles] %@", message)
    }

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let type: String
        let id: String
        let cigaretteStyleId: String?
        let cigaretteStyleID: String?
        let name: String
        let author: String?
        let license: String?
        let preview: String?
        let paletteBase: String?
        let brand: String?
        let subtitle: String?
        let palette: Palette?
        let artwork: Artwork?
        let geometry: Geometry?
    }
    private struct Palette: Decodable {
        let body: [String]?
        let lid: [String]?
        let foil: String?
        let edge: String?
        let fold: String?
        let rim: [String]?
        let basin: [String]?
        let trim: String?
        let bodyStroke: String?
        let highlight: String?
        let handleFill: String?
        let handleStroke: String?
        let handleGlyph: String?
        let flame: [String]?
    }
    private struct Artwork: Decodable {
        let front: String?
        let body: String?
        let scaledBody: String?
        let lidOutside: String?
        let lidOutsideOpen: String?
        let lidInside: String? // Legacy presence keeps inside-only packages eligible for the base style.
        let whole: String?
    }
    private struct Geometry: Decodable {
        /// Normalized [x, y, width, height] on the ashtray's 320 × 210 design canvas.
        let basin: [Double]?
        let type: String?
        let lidBandFraction: Double?
        let frontAspectRatio: Double?
        let rowCounts: [Int]?
        let cigaretteCount: Int?
        let cigaretteDiameterMM: Double?
    }

    private init() {
        reload()
    }

    func reload() {
        diagnostics.removeAll(keepingCapacity: true)
        totalPackageBytes = 0
        cigaretteBoxes = CigaretteBoxStyle.builtIns
        ashtrays = AshtrayStyle.builtIns
        lighters = LighterStyle.builtIns
        var boxIDs = builtInIDs(for: "cigaretteBox")
        var ashtrayIDs = builtInIDs(for: "ashtray")
        var lighterIDs = builtInIDs(for: "lighter")
        if let bundledRoot = Bundle.module.resourceURL?.appendingPathComponent("Resources/StylePackages", isDirectory: true) {
            let bundledBoxes = bundledRoot.appendingPathComponent("cigarette-boxes", isDirectory: true)
            let bundledAshtrays = bundledRoot.appendingPathComponent("ashtrays", isDirectory: true)
            let bundledLighters = bundledRoot.appendingPathComponent("lighters", isDirectory: true)
            let boxStyles = loadPackages(in: bundledBoxes, expectedType: "cigaretteBox", initialIDs: boxIDs) { [self] manifest, directory in
                try makeBoxStyle(manifest, directory: directory)
            }
            let trayStyles = loadPackages(in: bundledAshtrays, expectedType: "ashtray", initialIDs: ashtrayIDs) { [self] manifest, directory in
                try makeAshtrayStyle(manifest, directory: directory)
            }
            let lighterStyles = loadPackages(in: bundledLighters, expectedType: "lighter", initialIDs: lighterIDs) { [self] manifest, directory in
                try makeLighterStyle(manifest, directory: directory)
            }
            cigaretteBoxes += boxStyles
            ashtrays += trayStyles
            lighters += lighterStyles
            boxIDs.formUnion(boxStyles.map { Self.packageID(from: $0.id) })
            ashtrayIDs.formUnion(trayStyles.map { Self.packageID(from: $0.id) })
            lighterIDs.formUnion(lighterStyles.map { Self.packageID(from: $0.id) })
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logDiagnostic(tr("无法定位用户 Application Support 目录"))
            return
        }
        let root = appSupport.appendingPathComponent("DeskPuff/Styles", isDirectory: true)
        let boxRoot = root.appendingPathComponent("cigarette-boxes", isDirectory: true)
        let trayRoot = root.appendingPathComponent("ashtrays", isDirectory: true)
        let lighterRoot = root.appendingPathComponent("lighters", isDirectory: true)
        for folder in [boxRoot, trayRoot, lighterRoot] {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        cigaretteBoxes += loadPackages(in: boxRoot, expectedType: "cigaretteBox", initialIDs: boxIDs) { [self] manifest, directory in
            try makeBoxStyle(manifest, directory: directory)
        }
        ashtrays += loadPackages(in: trayRoot, expectedType: "ashtray", initialIDs: ashtrayIDs) { [self] manifest, directory in
            try makeAshtrayStyle(manifest, directory: directory)
        }
        lighters += loadPackages(in: lighterRoot, expectedType: "lighter", initialIDs: lighterIDs) { [self] manifest, directory in
            try makeLighterStyle(manifest, directory: directory)
        }
    }

    func importPackage(from source: URL, expectedType: String) throws {
        guard ["cigaretteBox", "ashtray", "lighter"].contains(expectedType) else { throw PackageError.invalid(tr("未知样式类型")) }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw PackageError.invalid(tr("样式包必须是普通文件夹")) }
        let manifestURL = source.appendingPathComponent("manifest.json")
        _ = try fileSize(manifestURL, maximum: maxManifestBytes)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.type == expectedType, isValidID(manifest.id) else { throw PackageError.invalid(tr("样式类型或 ID 无效")) }
        let root = try userStyleRoot(for: expectedType)
        let destination = root.appendingPathComponent(manifest.id, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else { throw PackageError.invalid(tr("该 ID 的样式文件夹已存在")) }
        try fileManager.copyItem(at: source, to: destination)
        reload()
        let loaded: Bool
        switch expectedType {
        case "cigaretteBox": loaded = cigaretteBoxes.contains { $0.id == "user:\(manifest.id)" }
        case "ashtray": loaded = ashtrays.contains { $0.id == "user:\(manifest.id)" }
        default: loaded = lighters.contains { $0.id == "user:\(manifest.id)" }
        }
        guard loaded else {
            try? fileManager.removeItem(at: destination)
            reload()
            throw PackageError.invalid(diagnostics.last ?? tr("样式包校验失败"))
        }
    }

    func removePackage(styleID: String, expectedType: String) throws {
        guard styleID.hasPrefix("user:") else { throw PackageError.invalid(tr("内置样式不能移除")) }
        let rawID = String(styleID.dropFirst(5))
        let root = try userStyleRoot(for: expectedType)
        let directory = root.appendingPathComponent(rawID, isDirectory: true)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        _ = try fileSize(manifestURL, maximum: maxManifestBytes)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.id == rawID, manifest.type == expectedType else { throw PackageError.invalid(tr("样式包目录与 manifest 不匹配")) }
        try fileManager.removeItem(at: directory)
        reload()
    }

    private func userStyleRoot(for type: String) throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PackageError.invalid(tr("无法定位用户 Application Support 目录"))
        }
        let category = type == "cigaretteBox" ? "cigarette-boxes" : type == "ashtray" ? "ashtrays" : "lighters"
        let root = appSupport.appendingPathComponent("DeskPuff/Styles/\(category)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func loadPackages<T>(in root: URL, expectedType: String, initialIDs: Set<String>? = nil,
                                 makeStyle: (Manifest, URL) throws -> T) -> [T] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        let directories = children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var styles: [T] = []
        var seenIDs = initialIDs ?? builtInIDs(for: expectedType)
        for directory in directories.prefix(maxPackagesPerKind) {
            do {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let manifestURL = directory.appendingPathComponent("manifest.json")
                guard try fileSize(manifestURL, maximum: maxManifestBytes) <= maxManifestBytes else {
                    throw PackageError.invalid(tr("manifest.json 超过 1 MB"))
                }
                let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
                guard manifest.schemaVersion == 1 else { throw PackageError.invalid(tr("不支持的 schemaVersion")) }
                guard manifest.type == expectedType else { throw PackageError.invalid(tr("样式类型与目录不匹配")) }
                guard isValidID(manifest.id), !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw PackageError.invalid(tr("id 或 name 无效"))
                }
                guard directory.lastPathComponent == manifest.id else {
                    throw PackageError.invalid(tr("文件夹名称必须与 manifest 的 id 相同"))
                }
                guard !seenIDs.contains(manifest.id) else {
                    throw PackageError.invalid(tr("id 与内置或其他样式重复"))
                }
                let packageByteCheckpoint = totalPackageBytes
                do {
                    let style = try makeStyle(manifest, directory)
                    styles.append(style)
                } catch {
                    totalPackageBytes = packageByteCheckpoint
                    throw error
                }
                seenIDs.insert(manifest.id)
            } catch {
                logDiagnostic("\(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if directories.count > maxPackagesPerKind {
            logDiagnostic(tr("{{0}}: 仅检查前 {{1}} 个样式目录", root.lastPathComponent, maxPackagesPerKind))
        }
        return styles
    }

    private enum PackageError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case let .invalid(message) = self { return message }
            return tr("样式包无效")
        }
    }

    private func builtInIDs(for type: String) -> Set<String> {
        switch type {
        case "cigaretteBox": Set(CigaretteBoxStyle.builtIns.map(\.id))
        case "ashtray": Set(AshtrayStyle.builtIns.map(\.id))
        default: Set(LighterStyle.builtIns.map(\.id))
        }
    }

    private static func packageID(from styleID: String) -> String {
        styleID.hasPrefix("user:") ? String(styleID.dropFirst(5)) : styleID
    }

    private func isValidID(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil
    }

    private func fileSize(_ url: URL, maximum: Int) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0, size <= maximum else {
            throw PackageError.invalid(tr("文件不存在、不是普通文件或超过大小限制"))
        }
        return size
    }

    private func loadImage(_ relativePath: String?, from directory: URL, packageBytes: inout Int) throws -> NSImage? {
        guard let relativePath else { return nil }
        let pathComponents = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !pathComponents.contains(".."), !pathComponents.contains("."), !pathComponents.contains(""),
              URL(fileURLWithPath: relativePath).pathExtension.lowercased() == "png" else {
            throw PackageError.invalid(tr("图片路径必须是包内的相对 PNG 路径"))
        }
        let root = directory.standardizedFileURL.path + "/"
        let url = directory.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root) else { throw PackageError.invalid(tr("图片路径越出了样式目录")) }
        var cursor = directory
        for component in relativePath.split(separator: "/").dropLast() {
            cursor.appendPathComponent(String(component), isDirectory: true)
            guard try cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw PackageError.invalid(tr("图片路径不能经过符号链接"))
            }
        }
        let size = try fileSize(url, maximum: maxImageBytes)
        packageBytes += size
        guard packageBytes <= maxPackageBytes else { throw PackageError.invalid(tr("样式包图片总量超过 64 MB")) }
        guard totalPackageBytes + size <= maxTotalPackageBytes else { throw PackageError.invalid(tr("全部外部样式图片总量超过 256 MB")) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              bitmap.pixelsWide <= maxImageDimension, bitmap.pixelsHigh <= maxImageDimension,
              let image = NSImage(data: data) else {
            throw PackageError.invalid(tr("PNG 无法解码或尺寸超过 4096 × 4096"))
        }
        totalPackageBytes += size
        return image
    }

    private func parsedColor(_ value: String?, fallback: NSColor) throws -> NSColor {
        guard let value else { return fallback }
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6 || hex.count == 8, let number = UInt64(hex, radix: 16) else {
            throw PackageError.invalid(tr("颜色必须是 #RRGGBB 或 #RRGGBBAA"))
        }
        let red = CGFloat((number >> (hex.count == 8 ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((number >> (hex.count == 8 ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((number >> (hex.count == 8 ? 8 : 0)) & 0xFF) / 255
        let alpha = hex.count == 8 ? CGFloat(number & 0xFF) / 255 : 1
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    private func parsedColors(_ values: [String]?, fallback: [NSColor]) throws -> [NSColor] {
        guard let values else { return fallback }
        guard (2...4).contains(values.count) else { throw PackageError.invalid(tr("渐变色需提供 2 到 4 个颜色")) }
        return try values.map { try parsedColor($0, fallback: .black) }
    }

    private func makeBoxStyle(_ manifest: Manifest, directory: URL) throws -> CigaretteBoxStyle {
        let base = CigaretteBoxStyle.paletteBase(manifest.paletteBase)
        var packageBytes = 0
        let preview = try loadImage(manifest.preview, from: directory, packageBytes: &packageBytes)
        let front = try loadImage(manifest.artwork?.front, from: directory, packageBytes: &packageBytes)
        let body = try loadImage(manifest.artwork?.body, from: directory, packageBytes: &packageBytes)
        let scaledBody = try loadImage(manifest.artwork?.scaledBody, from: directory, packageBytes: &packageBytes)
        let lidOutside = try loadImage(manifest.artwork?.lidOutside, from: directory, packageBytes: &packageBytes)
        let lidOutsideOpen = try loadImage(manifest.artwork?.lidOutsideOpen, from: directory, packageBytes: &packageBytes)
        let hasExteriorArtwork = [front, body, scaledBody, lidOutside, lidOutsideOpen].contains { $0 != nil }
        guard hasExteriorArtwork || manifest.artwork?.lidInside != nil || manifest.palette != nil else {
            throw PackageError.invalid(tr("样式包至少需要一张外观 PNG 或 palette"))
        }
        let palette = manifest.palette
        return CigaretteBoxStyle(
            id: "user:\(manifest.id)", name: manifest.name, brand: manifest.brand ?? manifest.name,
            subtitle: manifest.subtitle ?? "COMMUNITY DESIGN",
            body: try parsedColors(palette?.body, fallback: base.body),
            lid: try parsedColors(palette?.lid, fallback: base.lid),
            foil: try parsedColor(palette?.foil, fallback: base.foil),
            edge: try parsedColor(palette?.edge, fallback: base.edge),
            fold: try parsedColor(palette?.fold, fallback: base.fold), previewArtwork: preview,
            frontArtwork: front,
            bodyArtwork: body, scaledBodyArtwork: scaledBody,
            lidOutsideArtwork: lidOutside, lidOutsideOpenArtwork: lidOutsideOpen,
            geometry: try boxGeometry(manifest.geometry),
            cigaretteStyleID: manifest.cigaretteStyleId ?? manifest.cigaretteStyleID
        )
    }

    private func boxGeometry(_ value: Geometry?) throws -> CigaretteBoxGeometry {
        guard let value else { return .standard }
        let type = value.type ?? "standard-hard"
        guard ["standard-hard", "slim-hard"].contains(type) else {
            throw PackageError.invalid(tr("geometry.type 仅支持 standard-hard 或 slim-hard"))
        }
        let fraction = value.lidBandFraction ?? 25.0 / 86.0
        guard (0.2...0.42).contains(fraction) else {
            throw PackageError.invalid(tr("geometry.lidBandFraction 必须在 0.2 到 0.42 之间"))
        }
        let rows = value.rowCounts ?? [7, 6, 7]
        let aspect = value.frontAspectRatio.map { CGFloat($0) }
        if let aspect, !(0.4...0.8).contains(aspect) {
            throw PackageError.invalid(tr("geometry.frontAspectRatio 必须在 0.4 到 0.8 之间"))
        }
        let count = value.cigaretteCount ?? rows.reduce(0, +)
        guard !rows.isEmpty, rows.count <= 4, rows.allSatisfy({ (1...10).contains($0) }),
              (1...30).contains(count), rows.reduce(0, +) == count else {
            throw PackageError.invalid(tr("geometry.rowCounts 与 cigaretteCount 不匹配"))
        }
        let diameter = value.cigaretteDiameterMM.map { CGFloat($0) }
        if let diameter, !(4.5...10.0).contains(diameter) {
            throw PackageError.invalid(tr("geometry.cigaretteDiameterMM 必须在 4.5 到 10 之间"))
        }
        return CigaretteBoxGeometry(type: type, lidBandFraction: CGFloat(fraction), frontAspectRatio: aspect, rowCounts: rows,
                                    cigaretteCount: count, cigaretteDiameterMM: diameter)
    }

    private func makeAshtrayStyle(_ manifest: Manifest, directory: URL) throws -> AshtrayStyle {
        let base = AshtrayStyle.builtIns.first { $0.id == manifest.paletteBase } ?? .default
        var packageBytes = 0
        let preview = try loadImage(manifest.preview, from: directory, packageBytes: &packageBytes)
        let artwork = try loadImage(manifest.artwork?.whole, from: directory, packageBytes: &packageBytes)
        guard artwork != nil || manifest.palette != nil else {
            throw PackageError.invalid(tr("样式包至少需要一张外观 PNG 或 palette"))
        }
        let basin: NSRect?
        if let values = manifest.geometry?.basin {
            guard values.count == 4, values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
                  values[2] > 0, values[3] > 0,
                  values[0] + values[2] <= 1, values[1] + values[3] <= 1 else {
                throw PackageError.invalid(tr("geometry.basin 必须是画布内的归一化 [x,y,width,height]"))
            }
            basin = NSRect(x: values[0] * 320, y: values[1] * 210,
                           width: values[2] * 320, height: values[3] * 210)
        } else { basin = nil }
        let palette = manifest.palette
        return AshtrayStyle(
            id: "user:\(manifest.id)", name: manifest.name,
            body: try parsedColors(palette?.body, fallback: base.body),
            rim: try parsedColors(palette?.rim, fallback: base.rim),
            basin: try parsedColors(palette?.basin, fallback: base.basin),
            trim: try parsedColor(palette?.trim, fallback: base.trim),
            bodyStroke: try parsedColor(palette?.bodyStroke, fallback: base.bodyStroke),
            highlight: try parsedColor(palette?.highlight, fallback: base.highlight),
            handleFill: try parsedColor(palette?.handleFill, fallback: base.handleFill),
            handleStroke: try parsedColor(palette?.handleStroke, fallback: base.handleStroke),
            handleGlyph: try parsedColor(palette?.handleGlyph, fallback: base.handleGlyph),
            artwork: artwork, basinFrame: basin, previewArtwork: preview
        )
    }

    private func makeLighterStyle(_ manifest: Manifest, directory: URL) throws -> LighterStyle {
        let base = LighterStyle.builtIns.first { $0.id == manifest.paletteBase } ?? .default
        var packageBytes = 0
        let preview = try loadImage(manifest.preview, from: directory, packageBytes: &packageBytes)
        let artwork = try loadImage(manifest.artwork?.whole, from: directory, packageBytes: &packageBytes)
        guard artwork != nil || manifest.palette != nil else {
            throw PackageError.invalid(tr("样式包至少需要一张外观 PNG 或 palette"))
        }
        return LighterStyle(id: "user:\(manifest.id)", name: manifest.name,
                            body: try parsedColors(manifest.palette?.body, fallback: base.body),
                            metal: try parsedColors(manifest.palette?.rim, fallback: base.metal),
                            flame: try parsedColors(manifest.palette?.flame, fallback: base.flame),
                            artwork: artwork, previewArtwork: preview)
    }
}
