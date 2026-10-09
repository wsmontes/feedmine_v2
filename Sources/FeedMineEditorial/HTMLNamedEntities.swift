// Owns: the complete HTML 4.01 named character reference table used by readable text.
// v1 lesson (IN-6): a hand-curated subset surfaced a new bug for every unlisted entity
// (v1 commits f1ac4b75, 382b9546). The table is total for HTML 4.01; unknown names stay literal.

enum HTMLNamedEntities {
    /// Name → scalar. Names are case-sensitive (`Agrave` ≠ `agrave`).
    static let table: [String: String] = {
        var map: [String: String] = [:]
        func add(_ name: String, _ value: UInt32) {
            if let scalar = Unicode.Scalar(value) { map[name] = String(Character(scalar)) }
        }
        // ISO 8859-1, U+00A0...U+00FF in code point order.
        let latin1 = ["nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf",
            "laquo", "not", "shy", "reg", "macr", "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot",
            "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest",
            "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc", "Euml",
            "Igrave", "Iacute", "Icirc", "Iuml", "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times",
            "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
            "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute", "ecirc", "euml",
            "igrave", "iacute", "icirc", "iuml", "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "divide",
            "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml"]
        for (offset, name) in latin1.enumerated() { add(name, 0xA0 + UInt32(offset)) }
        // Greek, contiguous runs (U+03A2 is unassigned, so Sigma restarts the run).
        for (offset, name) in ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa",
            "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho"].enumerated() { add(name, 0x391 + UInt32(offset)) }
        for (offset, name) in ["Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega"].enumerated() {
            add(name, 0x3A3 + UInt32(offset))
        }
        for (offset, name) in ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa",
            "lambda", "mu", "nu", "xi", "omicron", "pi", "rho", "sigmaf", "sigma", "tau", "upsilon", "phi", "chi",
            "psi", "omega"].enumerated() { add(name, 0x3B1 + UInt32(offset)) }
        let singles: [(String, UInt32)] = [
            // Markup-significant and Latin Extended.
            ("quot", 34), ("amp", 38), ("apos", 39), ("lt", 60), ("gt", 62),
            ("OElig", 338), ("oelig", 339), ("Scaron", 352), ("scaron", 353), ("Yuml", 376), ("fnof", 402),
            ("circ", 710), ("tilde", 732), ("thetasym", 977), ("upsih", 978), ("piv", 982),
            // General punctuation.
            ("ensp", 8194), ("emsp", 8195), ("thinsp", 8201), ("zwnj", 8204), ("zwj", 8205), ("lrm", 8206),
            ("rlm", 8207), ("ndash", 8211), ("mdash", 8212), ("lsquo", 8216), ("rsquo", 8217), ("sbquo", 8218),
            ("ldquo", 8220), ("rdquo", 8221), ("bdquo", 8222), ("dagger", 8224), ("Dagger", 8225), ("bull", 8226),
            ("hellip", 8230), ("permil", 8240), ("prime", 8242), ("Prime", 8243), ("lsaquo", 8249), ("rsaquo", 8250),
            ("oline", 8254), ("frasl", 8260), ("euro", 8364),
            // Letterlike symbols and arrows.
            ("image", 8465), ("weierp", 8472), ("real", 8476), ("trade", 8482), ("alefsym", 8501),
            ("larr", 8592), ("uarr", 8593), ("rarr", 8594), ("darr", 8595), ("harr", 8596), ("crarr", 8629),
            ("lArr", 8656), ("uArr", 8657), ("rArr", 8658), ("dArr", 8659), ("hArr", 8660),
            // Mathematical operators.
            ("forall", 8704), ("part", 8706), ("exist", 8707), ("empty", 8709), ("nabla", 8711), ("isin", 8712),
            ("notin", 8713), ("ni", 8715), ("prod", 8719), ("sum", 8721), ("minus", 8722), ("lowast", 8727),
            ("radic", 8730), ("prop", 8733), ("infin", 8734), ("ang", 8736), ("and", 8743), ("or", 8744),
            ("cap", 8745), ("cup", 8746), ("int", 8747), ("there4", 8756), ("sim", 8764), ("cong", 8773),
            ("asymp", 8776), ("ne", 8800), ("equiv", 8801), ("le", 8804), ("ge", 8805), ("sub", 8834),
            ("sup", 8835), ("nsub", 8836), ("sube", 8838), ("supe", 8839), ("oplus", 8853), ("otimes", 8855),
            ("perp", 8869), ("sdot", 8901),
            // Technical, geometric shapes and miscellaneous symbols.
            ("lceil", 8968), ("rceil", 8969), ("lfloor", 8970), ("rfloor", 8971), ("lang", 9001), ("rang", 9002),
            ("loz", 9674), ("spades", 9824), ("clubs", 9827), ("hearts", 9829), ("diams", 9830)
        ]
        for (name, value) in singles { add(name, value) }
        // Readable text renders a non-breaking space as an ordinary space (existing H4/H5 contract).
        map["nbsp"] = " "
        return map
    }()
}
