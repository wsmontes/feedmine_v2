// Owns: one material-occurrence key shared by Editorial and durable Publication.
// Inputs are readable normalized title/text; transport locators remain untouched.
public enum MaterialContentIdentity {
    public static func key(title: String?, text: String?, primaryMedia: String?) -> String {
        func collapse(_ value: String?) -> String { (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        return collapse(title) + "\u{1F}" + collapse(text) + "\u{1F}" + (primaryMedia.map(ContentLocatorIdentity.normalizedLink) ?? "")
    }
}
