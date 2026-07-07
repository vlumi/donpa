// Readable-key wire format, new in the family vocabulary (`{"grid":{"size":…}}`).
// A save written in the old classic/modern shape fails to decode and is discarded
// by the loader — accepted: the 0.3.0 release already resets scores and drops
// in-progress saves (a mid-game is a shrug; records are the thing we never lose).
extension GameConfig: Codable {
    private enum CaseKey: String, CodingKey { case basic, grid, hive, practice }
    private enum BasicKey: String, CodingKey { case preset }
    private enum CustomKey: String, CodingKey { case size, density, edges }
    private enum PracticeKey: String, CodingKey { case size }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        if let basic = try? c.nestedContainer(keyedBy: BasicKey.self, forKey: .basic) {
            self = .basic(try basic.decode(BasicPreset.self, forKey: .preset))
            return
        }
        if let practice = try? c.nestedContainer(keyedBy: PracticeKey.self, forKey: .practice) {
            self = .practice(try practice.decode(BoardSize.self, forKey: .size))
            return
        }
        for (key, family) in [(CaseKey.grid, BoardFamily.grid), (.hive, .hive)] {
            if let custom = try? c.nestedContainer(keyedBy: CustomKey.self, forKey: key) {
                let size = try custom.decode(BoardSize.self, forKey: .size)
                let density = try custom.decode(Density.self, forKey: .density)
                let edges = try custom.decode(BoardEdges.self, forKey: .edges)
                guard let config = GameConfig.custom(family, size, density, edges) else { break }
                self = config
                return
            }
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unknown GameConfig case"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .basic(let preset):
            var basic = c.nestedContainer(keyedBy: BasicKey.self, forKey: .basic)
            try basic.encode(preset, forKey: .preset)
        case .grid(let size, let density, let edges), .hive(let size, let density, let edges):
            let key: CaseKey = family == .grid ? .grid : .hive
            var custom = c.nestedContainer(keyedBy: CustomKey.self, forKey: key)
            try custom.encode(size, forKey: .size)
            try custom.encode(density, forKey: .density)
            try custom.encode(edges, forKey: .edges)
        case .practice(let size):
            var practice = c.nestedContainer(keyedBy: PracticeKey.self, forKey: .practice)
            try practice.encode(size, forKey: .size)
        }
    }
}
