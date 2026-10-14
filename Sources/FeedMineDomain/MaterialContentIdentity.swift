// Owns: one material-occurrence key shared by Editorial and durable Publication.
// Inputs are readable normalized title/text; transport locators remain untouched.
public enum MaterialContentIdentity {
    public static func key(title: String?, text: String?, primaryMedia: String?,
        declaredBody: String? = nil, bodyObserved: Bool = false) -> String {
        func collapse(_ value: String?) -> String { (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        let legacy = collapse(title) + "\u{1F}" + collapse(text) + "\u{1F}"
            + (primaryMedia.map(ContentLocatorIdentity.normalizedLink) ?? "")
        // Unknown legacy material keeps its exact original key. Observed absence is not
        // unknown: a publisher removing <content> must differ from the last known body.
        if let declaredBody { return legacy + "\u{1F}body\u{1F}" + collapse(declaredBody) }
        if bodyObserved { return legacy + "\u{1F}body-absent" }
        return legacy
    }
}
