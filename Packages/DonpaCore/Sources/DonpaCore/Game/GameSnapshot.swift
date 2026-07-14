import Foundation

/// The camera view saved with a game, stored window-independently so it
/// restores on another window size or device: `centerX`/`centerY` are the
/// centre as a normalized board point (0…1); `scale` is world-units-per-point
/// (bigger = more zoomed out).
public struct CameraView: Codable, Sendable, Equatable {
    public let centerX: Double
    public let centerY: Double
    public let scale: Double

    public init(centerX: Double, centerY: Double, scale: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
    }
}

/// A compact, `Codable` capture of an in-progress game. The format is
/// **additive**: new fields are optional-with-default so older saves still
/// restore; only `config` and `mines` are required. Bump `currentVersion` only
/// for a *breaking* change — older apps then refuse the newer save rather than
/// mis-read it.
public struct GameSnapshot: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let config: GameConfig
    public let mines: Set<Coord>
    public let revealed: Set<Coord>
    public let flagged: Set<Coord>
    public let questioned: Set<Coord>
    public let status: GameStatus
    public let revealedSafeCount: Int
    public let lossCoord: Coord?
    public let elapsedCentiseconds: Int
    public let camera: CameraView?
    public let inputMode: InputMode
    /// The last-played stamp: sorts the in-progress list, picks auto-resume.
    public let updatedAt: Date

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        config = try c.decode(GameConfig.self, forKey: .config)
        mines = try c.decode(Set<Coord>.self, forKey: .mines)
        revealed = try c.decodeIfPresent(Set<Coord>.self, forKey: .revealed) ?? []
        flagged = try c.decodeIfPresent(Set<Coord>.self, forKey: .flagged) ?? []
        questioned = try c.decodeIfPresent(Set<Coord>.self, forKey: .questioned) ?? []
        status = try c.decodeIfPresent(GameStatus.self, forKey: .status) ?? .playing
        revealedSafeCount = try c.decodeIfPresent(Int.self, forKey: .revealedSafeCount) ?? 0
        lossCoord = try c.decodeIfPresent(Coord.self, forKey: .lossCoord)
        elapsedCentiseconds =
            try c.decodeIfPresent(Int.self, forKey: .elapsedCentiseconds) ?? 0
        camera = try c.decodeIfPresent(CameraView.self, forKey: .camera)
        inputMode = try c.decodeIfPresent(InputMode.self, forKey: .inputMode) ?? .reveal
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    /// nil unless the game is genuinely in progress.
    public init?(
        game: Game, config: GameConfig, elapsedCentiseconds: Int, camera: CameraView? = nil,
        inputMode: InputMode = .reveal, updatedAt: Date = Date()
    ) {
        guard game.status == .playing else { return nil }
        self.version = Self.currentVersion
        self.config = config
        self.mines = game.board.mineCoords
        self.revealed = game.board.revealedCoords
        self.flagged = game.board.flaggedCoords
        self.questioned = game.board.questionedCoords
        self.status = game.status
        self.revealedSafeCount = game.revealedSafeCount
        self.lossCoord = game.lossCoord
        self.elapsedCentiseconds = elapsedCentiseconds
        self.camera = camera
        self.inputMode = inputMode
        self.updatedAt = updatedAt
    }

    /// Builds from captured inputs so the heavy board scan can run off the
    /// main actor.
    public init?(inputs: GameViewModel.SnapshotInputs) {
        self.init(
            game: inputs.game, config: inputs.config,
            elapsedCentiseconds: inputs.elapsedCentiseconds, camera: inputs.camera,
            inputMode: inputs.inputMode)
    }

    public func makeGame() -> Game {
        Game.restored(from: self)
    }

    /// Whether the snapshot still matches what its symbolic `config` means in
    /// this build — a between-builds retune would otherwise restore a mangled,
    /// unwinnable board. Loaders discard inconsistent saves.
    public var isConsistent: Bool {
        guard !mines.isEmpty, mines.count == config.mineCount else { return false }
        let width = config.width
        let height = config.height
        func inBounds(_ c: Coord) -> Bool {
            c.x >= 0 && c.x < width && c.y >= 0 && c.y < height
        }
        return mines.allSatisfy(inBounds) && revealed.allSatisfy(inBounds)
            && flagged.allSatisfy(inBounds) && questioned.allSatisfy(inBounds)
            && (lossCoord.map(inBounds) ?? true)
    }

    /// Migration seam for a future `currentVersion` bump; identity today.
    public func migrated() -> GameSnapshot {
        self
    }
}
