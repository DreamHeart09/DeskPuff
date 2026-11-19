import Foundation

enum GameLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var name: String { self == .chinese ? "简体中文" : "English" }

    private static let key = "gameInterfaceLanguage"

    static var current: GameLanguage {
        if let saved = UserDefaults.standard.string(forKey: key), let language = Self(rawValue: saved) {
            return language
        }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }

    func save() { UserDefaults.standard.set(rawValue, forKey: Self.key) }
}

private let englishStrings: [String: String] = {
    guard let url = Bundle.module.url(forResource: "GameEnglish", withExtension: "json", subdirectory: "Resources"),
          let data = try? Data(contentsOf: url),
          let strings = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return strings
}()

func tr(_ key: String, _ arguments: Any...) -> String {
    let template = GameLanguage.current == .english ? englishStrings[key] ?? key : key
    guard !arguments.isEmpty else { return template }
    var result = ""
    var tail = template[...]
    while let open = tail.range(of: "{{"), let close = tail[open.upperBound...].range(of: "}}") {
        result += tail[..<open.lowerBound]
        let token = tail[open.upperBound..<close.lowerBound]
        if let index = Int(token), arguments.indices.contains(index) {
            result += String(describing: arguments[index])
        } else {
            result += tail[open.lowerBound..<close.upperBound]
        }
        tail = tail[close.upperBound...]
    }
    return result + tail
}
