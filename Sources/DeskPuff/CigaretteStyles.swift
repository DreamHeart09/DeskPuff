import AppKit
import Foundation
import Observation
import DeskPuffCore

struct CigaretteStyle: Identifiable {
    let manifest: CigaretteStyleManifest
    let isBuiltIn: Bool
    let packageDirectory: URL?
    let paperArtwork: NSImage?
    let filterArtwork: NSImage?
    let previewArtwork: NSImage?

    var id: String { isBuiltIn ? manifest.id : "user:\(manifest.id)" }
    var diameterScale: CGFloat { CGFloat(manifest.diameterMM / 7.8) }
}

@MainActor @Observable final class CigaretteStyleStore {
    static let shared = CigaretteStyleStore()

    private(set) var styles: [CigaretteStyle] = []
    private(set) var diagnostics: [String] = []
    private let fileManager = FileManager.default
    private let maxPackages = 100
    private let maxManifestBytes = 1_048_576
    private let maxImageBytes = 16 * 1_048_576
    private let maxPackageBytes = 64 * 1_048_576
    private let maxTotalImageBytes = 256 * 1_048_576
    private let maxImageDimension = 4096
    private var totalImageBytes = 0

    private init() { reload() }

    private static let defaultPresetID = "cigarette-zhonghua-classic"

    // Smoke multipliers tune the game effect. They do not represent measured emissions.
    static let builtInManifests: [CigaretteStyleManifest] = [
        CigaretteStyleManifest(id: "cigarette-zhonghua-classic", name: "中华（硬）", diameterMM: 7.8,
                               paper: .init(color: "#F6F3EB", shade: "#D9D6CE"),
                               filter: .init(color: "#BD8C51", highlight: "#E3C18D", shade: "#8D5E35", band: "#A24236"),
                               smoke: .init(emissionMultiplier: 1.00)),
        CigaretteStyleManifest(id: "cigarette-baisha-hard", name: "白沙（硬）", diameterMM: 7.8,
                               paper: .init(color: "#F6F5EF", shade: "#D8D9D1"),
                               filter: .init(color: "#C29D6B", highlight: "#E6C99C", shade: "#94704D", band: "#A08258"),
                               smoke: .init(emissionMultiplier: 0.94)),
        CigaretteStyleManifest(id: "cigarette-hongtashan-classic1956", name: "红塔山（硬经典1956）", diameterMM: 7.8,
                               paper: .init(color: "#F6F5F0", shade: "#D7D8D1"),
                               filter: .init(color: "#CEA773", highlight: "#EDCFA1", shade: "#98724C", band: "#AD4A41"),
                               smoke: .init(emissionMultiplier: 0.98)),
        CigaretteStyleManifest(id: "cigarette-liqun-new", name: "利群（新版）", diameterMM: 7.8,
                               paper: .init(color: "#F5F6F3", shade: "#D5D8D4"),
                               filter: .init(color: "#C49860", highlight: "#EAC594", shade: "#89613F", band: "#9D393E"),
                               smoke: .init(emissionMultiplier: 0.95)),
        CigaretteStyleManifest(id: "cigarette-shuangxi-classic1906", name: "双喜（硬经典1906）", diameterMM: 7.8,
                               paper: .init(color: "#F7F3EA", shade: "#DCD4C8"),
                               filter: .init(color: "#A4784E", highlight: "#D1AB7E", shade: "#735036", band: "#CEAA69"),
                               smoke: .init(emissionMultiplier: 1.01)),
        CigaretteStyleManifest(id: "cigarette-furongwang-hard", name: "芙蓉王（硬）", diameterMM: 7.8,
                               paper: .init(color: "#F8F5EE", shade: "#DBD8CC"),
                               filter: .init(color: "#CCAD75", highlight: "#F0D6A5", shade: "#997648", band: "#C0A15F"),
                               smoke: .init(emissionMultiplier: 1.02)),
        CigaretteStyleManifest(id: "cigarette-diamond-lotus-hard", name: "钻石（荷花）", diameterMM: 7.8,
                               paper: .init(color: "#F6F6EF", shade: "#D8DBD1"),
                               filter: .init(color: "#E2D3AC", highlight: "#F6EDD1", shade: "#A49674", band: "#749375"),
                               smoke: .init(emissionMultiplier: 0.93)),
        CigaretteStyleManifest(id: "cigarette-yuxi-hexie", name: "玉溪（硬和谐）", diameterMM: 7.8,
                               paper: .init(color: "#F6F1E6", shade: "#DACFBE"),
                               filter: .init(color: "#996B50", highlight: "#C59A78", shade: "#694536", band: "#BD9A65"),
                               smoke: .init(emissionMultiplier: 1.00)),
        CigaretteStyleManifest(id: "cigarette-huangjinye-tianye", name: "黄金叶（天叶）", diameterMM: 7.8,
                               paper: .init(color: "#F6F3E9", shade: "#DCD5C6"),
                               filter: .init(color: "#D1B178", highlight: "#F1DAA8", shade: "#9F7950", band: "#B77944"),
                               smoke: .init(emissionMultiplier: 1.04)),
        CigaretteStyleManifest(id: "cigarette-huanghelou-1916-ruyi", name: "黄鹤楼（硬1916如意）", diameterMM: 7.8,
                               paper: .init(color: "#F7F4ED", shade: "#DBD7CB"),
                               filter: .init(color: "#DDC39A", highlight: "#F7E4BD", shade: "#A78961", band: "#BB9659"),
                               smoke: .init(emissionMultiplier: 0.92)),
        CigaretteStyleManifest(id: "cigarette-nanjing-xuanhemen", name: "南京（炫赫门）", diameterMM: 5.4,
                               paper: .init(color: "#F6F8F6", shade: "#D7E0DB"),
                               filter: .init(color: "#55797A", highlight: "#83ABAA", shade: "#345150", band: "#CCAE76"),
                               smoke: .init(emissionMultiplier: 0.74))
    ]

    private static let legacyPresetIDs: [String: String] = [
        "standard": defaultPresetID,
        "zhonghua-filter": defaultPresetID,
        "thick": defaultPresetID,
        "yunlan-fine": "cigarette-nanjing-xuanhemen",
        "fine": "cigarette-nanjing-xuanhemen",
        "slim": "cigarette-nanjing-xuanhemen"
    ]

    var defaultStyleID: String {
        get { resolve(UserDefaults.standard.string(forKey: "cigaretteStyleIDV1"))?.id ?? Self.defaultPresetID }
        set { UserDefaults.standard.set(newValue, forKey: "cigaretteStyleIDV1") }
    }

    var defaultStyle: CigaretteStyle {
        resolve(defaultStyleID) ?? Self.resolved(Self.builtInManifests[0])
    }

    func resolve(_ styleID: String?) -> CigaretteStyle? {
        guard let styleID else { return nil }
        let currentID = Self.legacyPresetIDs[styleID] ?? styleID
        return styles.first { $0.id == currentID || $0.manifest.id == currentID }
    }

    func style(for box: CigaretteBoxStyle) -> CigaretteStyle {
        let overrides = UserDefaults.standard.dictionary(forKey: "cigaretteStyleByBoxV1") as? [String: String] ?? [:]
        let overrideID = overrides[box.id]
        let bundledID = box.id == CigaretteBoxStyle.default.id
            ? Self.defaultPresetID
            : box.id.replacingOccurrences(of: "user:", with: "cigarette-", options: .anchored)
        // A packaged box with an old generic override now uses its dedicated preset.
        // Explicit current or custom associations still win.
        if let overrideID, Self.legacyPresetIDs[overrideID] == nil || box.cigaretteStyleID != bundledID,
           let override = resolve(overrideID) {
            return override
        }
        return resolve(box.cigaretteStyleID) ?? defaultStyle
    }

    func reload() {
        diagnostics.removeAll(keepingCapacity: true)
        totalImageBytes = 0
        styles = Self.builtInManifests.map(Self.resolved)
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            diagnostics.append(tr("无法定位用户 Application Support 目录"))
            return
        }
        let root = support.appendingPathComponent("DeskPuff/Styles/cigarettes", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        guard let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return }
        let directories = children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        var seen = Set(styles.map { $0.manifest.id }).union(Self.legacyPresetIDs.keys)
        for directory in directories.prefix(maxPackages) {
            let byteCheckpoint = totalImageBytes
            do {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let manifestURL = directory.appendingPathComponent("manifest.json")
                let manifestSize = try fileSize(manifestURL, maximum: maxManifestBytes)
                var packageBytes = manifestSize
                let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
                let manifest = try JSONDecoder().decode(CigaretteStyleManifest.self, from: data)
                if let error = manifest.validationError() { throw PackageError.invalid(error) }
                guard directory.lastPathComponent == manifest.id else { throw PackageError.invalid(tr("文件夹名必须与 manifest 的 id 相同")) }
                guard !seen.contains(manifest.id) else { throw PackageError.invalid(tr("id 与内置或其他样式重复")) }
                let paper = try loadImage(manifest.artwork?.paper, from: directory, packageBytes: &packageBytes)
                let filter = try loadImage(manifest.artwork?.filter, from: directory, packageBytes: &packageBytes)
                let preview = try loadImage(manifest.artwork?.preview, from: directory, packageBytes: &packageBytes)
                guard packageBytes <= maxPackageBytes else { throw PackageError.invalid(tr("样式包总量超过 64 MB")) }
                styles.append(CigaretteStyle(manifest: manifest, isBuiltIn: false, packageDirectory: directory,
                                             paperArtwork: paper, filterArtwork: filter, previewArtwork: preview))
                seen.insert(manifest.id)
            } catch {
                totalImageBytes = byteCheckpoint
                diagnostics.append("\(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if directories.count > maxPackages { diagnostics.append(tr("只检查了名称排序前 {{0}} 个香烟包", maxPackages)) }
    }

    func importPackage(from source: URL) throws {
        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard sourceValues.isDirectory == true, sourceValues.isSymbolicLink != true else { throw PackageError.invalid(tr("样式包必须是普通文件夹")) }
        let root = try userRoot()
        let manifestURL = source.appendingPathComponent("manifest.json")
        _ = try fileSize(manifestURL, maximum: maxManifestBytes)
        let manifest = try JSONDecoder().decode(CigaretteStyleManifest.self, from: Data(contentsOf: manifestURL))
        if let error = manifest.validationError() { throw PackageError.invalid(error) }
        guard resolve(manifest.id) == nil else { throw PackageError.invalid(tr("已存在相同样式 ID")) }
        let destination = root.appendingPathComponent(manifest.id, isDirectory: true)
        try fileManager.copyItem(at: source, to: destination)
        reload()
        guard resolve("user:\(manifest.id)") != nil else {
            try? fileManager.removeItem(at: destination)
            reload()
            throw PackageError.invalid(diagnostics.last ?? tr("样式包校验失败"))
        }
    }

    @discardableResult func save(_ manifest: CigaretteStyleManifest, asNewPackage: Bool = false) throws -> CigaretteStyle {
        if let error = manifest.validationError() { throw PackageError.invalid(error) }
        let root = try userRoot()
        let directory = root.appendingPathComponent(manifest.id, isDirectory: true)
        if asNewPackage {
            guard !fileManager.fileExists(atPath: directory.path), resolve(manifest.id) == nil else { throw PackageError.invalid(tr("已存在相同样式 ID")) }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            guard styles.contains(where: { $0.id == "user:\(manifest.id)" }) else { throw PackageError.invalid(tr("只能保存用户样式")) }
        }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            reload()
        } catch {
            if asNewPackage { try? fileManager.removeItem(at: directory) }
            throw error
        }
        guard let saved = resolve("user:\(manifest.id)") else { throw PackageError.invalid(diagnostics.last ?? tr("保存后加载失败")) }
        return saved
    }

    func copyForEditing(_ styleID: String) throws -> CigaretteStyle {
        guard let source = resolve(styleID) else { throw PackageError.invalid(tr("找不到要复制的香烟样式")) }
        var copy = source.manifest
        let stem = "\(copy.id.prefix(52))-custom"
        var candidate = stem
        var suffix = 2
        while resolve(candidate) != nil { candidate = "\(stem)-\(suffix)"; suffix += 1 }
        copy.id = candidate
        copy.name = String(tr("{{0}} · 自定义", copy.name).prefix(80))
        let destination = try userRoot().appendingPathComponent(candidate, isDirectory: true)
        if let sourceURL = source.packageDirectory {
            do {
                try fileManager.copyItem(at: sourceURL, to: destination)
                copy.artwork = source.manifest.artwork
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(copy).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
                reload()
                guard let result = resolve("user:\(candidate)") else { throw PackageError.invalid(tr("复制的样式无法重新加载")) }
                return result
            } catch {
                try? fileManager.removeItem(at: destination)
                reload()
                throw error
            }
        }
        return try save(copy, asNewPackage: true)
    }

    func remove(_ styleID: String) throws {
        guard let style = resolve(styleID), !style.isBuiltIn, let directory = style.packageDirectory else {
            throw PackageError.invalid(tr("内置样式不可删除"))
        }
        try fileManager.removeItem(at: directory)
        if defaultStyleID == style.id { defaultStyleID = Self.defaultPresetID }
        reload()
    }

    private func userRoot() throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PackageError.invalid(tr("无法定位用户 Application Support 目录"))
        }
        let root = support.appendingPathComponent("DeskPuff/Styles/cigarettes", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func loadImage(_ relativePath: String?, from directory: URL, packageBytes: inout Int) throws -> NSImage? {
        guard let relativePath else { return nil }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !components.contains("."), !components.contains(".."), !components.contains(""),
              URL(fileURLWithPath: relativePath).pathExtension.lowercased() == "png" else {
            throw PackageError.invalid(tr("图片路径必须是包内相对 PNG 路径"))
        }
        let root = directory.standardizedFileURL.path + "/"
        let url = directory.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root) else { throw PackageError.invalid(tr("图片路径越出了样式目录")) }
        var parent = directory
        for component in components.dropLast() {
            parent.appendPathComponent(String(component), isDirectory: true)
            guard try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw PackageError.invalid(tr("图片路径不能经过符号链接")) }
        }
        let size = try fileSize(url, maximum: maxImageBytes)
        packageBytes += size
        guard packageBytes <= maxPackageBytes, totalImageBytes + size <= maxTotalImageBytes else { throw PackageError.invalid(tr("样式包图片超过容量限制")) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
              bitmap.pixelsWide <= maxImageDimension, bitmap.pixelsHigh <= maxImageDimension,
              let image = NSImage(data: data) else { throw PackageError.invalid(tr("PNG 无法解码或尺寸超过 4096 × 4096")) }
        totalImageBytes += size
        return image
    }

    private func fileSize(_ url: URL, maximum: Int) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size >= 0, size <= maximum else {
            throw PackageError.invalid(tr("文件不存在、不是普通文件或超过大小限制"))
        }
        return size
    }

    private enum PackageError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(message) = self { return message }; return tr("香烟样式包无效") }
    }

    private static func resolved(_ manifest: CigaretteStyleManifest) -> CigaretteStyle {
        CigaretteStyle(manifest: manifest, isBuiltIn: true, packageDirectory: nil,
                       paperArtwork: nil, filterArtwork: nil, previewArtwork: nil)
    }
}

func cigaretteNSColor(_ hex: String) -> NSColor {
    let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return .white }
    return NSColor(calibratedRed: CGFloat((rgb >> 16) & 0xff) / 255,
                   green: CGFloat((rgb >> 8) & 0xff) / 255,
                   blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
}
