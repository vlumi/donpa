import DonpaCore
import SwiftUI

/// The per-family row builders for `BoardSelectionPicker`: the Basic preset
/// cards, the Grid/Hive size-chip row, and the Flat/Round edges glyph toggle.
/// Split from the picker (which keeps the pager + tabs) for the type-length cap.
extension BoardSelectionPicker {
    // MARK: Basic preset cards (row 1)

    /// The Basic page's own layout: three big preset cards stacked vertically,
    /// always all visible, each carrying its board facts and tagline inside — no
    /// Keyboard row 0 for Basic — ←/→ cycles the preset (family is ⌘1-3, not a row).
    var basicCards: some View {
        VStack(spacing: 6) {
            ForEach(BasicPreset.allCases, id: \.self) { preset in
                basicCard(preset)
            }
        }
        .modifier(FocusRing(focused: focusedRow == 0, inset: compact ? 3 : 6))
    }

    private func basicCard(_ preset: BasicPreset) -> some View {
        let selected = settings.basicPreset == preset
        return Button {
            settings.basicPreset = preset
            onFocusRow?(0)  // Basic's presets are its only row
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: preset.label)
                    .font(.headline)
                Text(verbatim: preset.detail)
                    .font(.subheadline.weight(.medium))
                Text(verbatim: preset.tagline)
                    .font(.subheadline)
                    .italic()
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.75))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(selected ? 0.14 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                selected
                                    ? Color.accentColor.opacity(0.6)
                                    : Color.primary.opacity(0.12)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SaveDot(show: index.presetHasSave(preset), onAccent: selected))
        .accessibilityLabel(Text(verbatim: "\(preset.label) — \(preset.detail)"))
        .modifier(SaveValue(hasSave: index.presetHasSave(preset)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Difficulty chips (row 1)

    /// The difficulty as six always-visible rank-insignia chips — NOT a drum: a
    /// horizontally-scrolling row inside a horizontally-swiped pager is two
    /// gestures fighting over the same axis. The selected tier's name, honest mine
    /// percentage (Hive runs denser), and tagline sit in the caption below.
    func densityChips(for family: BoardFamily) -> some View {
        let densityPath = Settings.densityPath(family)
        let selected = settings[keyPath: densityPath]
        return VStack(spacing: 6) {
            // All six chips in one row when there's room; 3 + 3 when not (matching
            // the size chips' wrap).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { densityRow(Density.allCases, densityPath) }
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        densityRow(Array(Density.allCases.prefix(3)), densityPath)
                    }
                    HStack(spacing: 8) {
                        densityRow(Array(Density.allCases.dropFirst(3)), densityPath)
                    }
                }
            }
            if let hint = lockedHint, hint.slot == 1 {
                detailLine(detail: String(localized: "Locked", bundle: .module), tagline: hint.text)
            } else {
                detailLine(
                    detail: "\(selected.label) · \(selected.detail(hex: family == .hive))",
                    tagline: selected.tagline)
            }
        }
    }

    @ViewBuilder private func densityRow(
        _ densities: [Density], _ densityPath: ReferenceWritableKeyPath<Settings, Density>
    ) -> some View {
        ForEach(densities, id: \.self) { density in
            densityChip(density, densityPath)
        }
    }

    private func densityChip(
        _ density: Density, _ densityPath: ReferenceWritableKeyPath<Settings, Density>
    ) -> some View {
        let selected = settings[keyPath: densityPath] == density
        let locked = !gates.rank(density)
        // Filtered by the choices ABOVE it (family + current size), so the dot only
        // lights when a save exists reachable down THIS path.
        let size = settings[keyPath: Settings.sizePath(settings.family)]
        let hasSave = index.densityHasSave(density, family: settings.family, size: size)
        return Button {
            if locked {
                if let req = UnlockEngine.requirement(rank: density) {
                    lockedHint = LockedHint(slot: 1, text: UnlockGates.requirementText(req))
                }
                return
            }
            settings[keyPath: densityPath] = density
            lockedHint = nil  // a real selection dismisses the teaser (user call)
            onFocusRow?(1)
        } label: {
            DensityInsignia.markImage(density)
                .resizable()
                .scaledToFit()
                .frame(width: insigniaWidth, height: chipContentHeight)
                .padding(.horizontal, 8)
                .padding(.vertical, 11)  // 22pt content + 2×11 = the 44pt tap target
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .modifier(SaveDot(show: hasSave, onAccent: selected))
        .modifier(LockBadge(locked: locked))
        .accessibilityLabel(Text(verbatim: density.label))
        .modifier(SaveValue(hasSave: hasSave))
        .modifier(
            LockValue(locked: locked, requirement: UnlockEngine.requirement(rank: density))
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Size chips (row 2)

    func sizeChips(for family: BoardFamily) -> some View {
        let sizePath = Settings.sizePath(family)
        // Drills stops at XL by design (see `GameConfig.practiceSizes`).
        let sizes = family == .practice ? GameConfig.practiceSizes : BoardSize.allCases
        let mid = (sizes.count + 1) / 2
        return VStack(spacing: 6) {
            // All chips in one row when there's room; two rows when not.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips(sizes, sizePath) }
                VStack(spacing: 6) {
                    HStack(spacing: 6) { chips(Array(sizes.prefix(mid)), sizePath) }
                    HStack(spacing: 6) { chips(Array(sizes.dropFirst(mid)), sizePath) }
                }
            }
            if let hint = lockedHint, hint.slot == 0 {
                detailLine(detail: String(localized: "Locked", bundle: .module), tagline: hint.text)
            } else {
                detailLine(
                    detail: settings[keyPath: sizePath].detail,
                    tagline: settings[keyPath: sizePath].tagline)
            }
        }
    }

    @ViewBuilder private func chips(
        _ sizes: [BoardSize], _ sizePath: ReferenceWritableKeyPath<Settings, BoardSize>
    ) -> some View {
        ForEach(sizes, id: \.self) { size in
            sizeChip(size, sizePath)
        }
    }

    private func sizeChip(
        _ size: BoardSize, _ sizePath: ReferenceWritableKeyPath<Settings, BoardSize>
    ) -> some View {
        let selected = settings[keyPath: sizePath] == size
        let locked = !gates.size(size)
        // Size sits just under family in the hierarchy, so it's filtered by family only.
        let hasSave = index.sizeHasSave(size, family: settings.family)
        return Button {
            if locked {
                // Teaser, not selection: the requirement takes the caption slot.
                if let req = UnlockEngine.requirement(size: size) {
                    lockedHint = LockedHint(slot: 0, text: UnlockGates.requirementText(req))
                }
                return
            }
            settings[keyPath: sizePath] = size
            lockedHint = nil  // a real selection dismisses the teaser (user call)
            onFocusRow?(0)  // size is row 0 (family stopped being a row long ago)
        } label: {
            Text(verbatim: size.label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                // Match the difficulty chips' pill size (same content height +
                // 8pt padding), so the size row never reads as bigger than it.
                // Scaled, not fixed: 22pt clipped grown text at accessibility sizes.
                .frame(height: chipContentHeight)
                .padding(.horizontal, 10)
                .padding(.vertical, 11)  // 22pt content + 2×11 = the 44pt tap target
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .modifier(SaveDot(show: hasSave, onAccent: selected))
        .modifier(LockBadge(locked: locked))
        .accessibilityLabel(Text(verbatim: "\(size.label) — \(size.detail)"))
        .modifier(SaveValue(hasSave: hasSave))
        .modifier(LockValue(locked: locked, requirement: UnlockEngine.requirement(size: size)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: Shared rows

    /// The caption under a chip row: board facts (bold) then tagline (italic). Each
    /// line has a stable height (scaled with Dynamic Type, constant per size) and
    /// shrinks to fit its width, so a long value scales down instead of wrapping
    /// and selection changes never move the rows.
    @ViewBuilder func detailLine(detail: String, tagline: String) -> some View {
        Group {
            if compact {
                // Short windows keep the tagline — it's the game's voice — but merge
                // it onto the facts line, shrink-to-fit, to reclaim the second row.
                (Text(verbatim: detail).font(.body.weight(.bold))
                    + Text(verbatim: "  ")
                    + Text(verbatim: tagline).font(.body).italic()
                    .foregroundColor(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: captionLineHeight)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 2) {
                    captionText(detail, weight: .bold, opacity: 1)
                    captionText(tagline, weight: .regular, opacity: 0.75, italic: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.snappy, value: detail)
    }

    /// One caption line: single line, fixed height, shrinks to fit width only.
    private func captionText(
        _ text: String, weight: Font.Weight, opacity: Double, italic: Bool = false
    ) -> some View {
        Text(verbatim: text)
            .font(.body.weight(weight))
            .italic(italic)
            .foregroundStyle(.primary.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(height: captionLineHeight)
    }

    // MARK: Drills' creed line

    /// Drills' standing caption: the mode's promise and its honest density,
    /// in the familiar facts-plus-tagline dress. It reads as the page's second
    /// row where Grid/Hive show the density row — the axis this mode fixed.
    var practiceCreed: some View {
        detailLine(
            detail: String(
                localized:
                    "Always solvable · \(Int((PracticeBoard.mineFraction * 100).rounded()))% mines",
                bundle: .module,
                comment: "Drills detail: the no-guess promise · N% mines"),
            tagline: String(localized: "No coin flips — logic wins", bundle: .module))
    }

    // MARK: Edges glyph toggle (row 3)

    // (SaveDot lives at file scope below — the shared corner-badge modifier.)

    func edgesToggle(for family: BoardFamily) -> some View {
        let edgesPath = Settings.edgesPath(family)
        let size = settings[keyPath: Settings.sizePath(family)]
        let density = settings[keyPath: Settings.densityPath(family)]
        return SegmentedGlyphPicker(
            values: BoardEdges.allCases,
            selection: Binding(
                get: { settings[keyPath: edgesPath] },
                set: { settings[keyPath: edgesPath] = $0 }),
            glyph: { .edges($0) }, label: { $0.label },
            onChange: {
                lockedHint = nil  // a real selection dismisses the teaser
                onFocusRow?(2)  // edges is row 2 — 3 left the ring dark
            },
            // Edges is the leaf: filtered by the full path above (family + size + density).
            badge: { index.edgesHasSave($0, family: family, size: size, density: density) },
            locked: { !gates.edges($0) },
            onLockedTap: { _ in
                // No caption of its own — the teaser borrows the density slot above.
                lockedHint = LockedHint(
                    slot: 1, text: UnlockGates.requirementText(.winAtLeastM))
            })
    }
}

/// A small badge marking a selector chip whose drill-down path holds an in-progress
/// save, so following lit chips down (family → size → density → edges) always lands on
/// a real saved board. Non-interactive, tucked in the chip's top-trailing corner; it
/// rides an overlay so it never changes the chip's layout.
///
/// Always present (scaled to zero when hidden) so it animates in step with the chip's
/// selection change instead of independently fading. On a chip that's currently filled
/// with the accent (`onAccent`), an accent dot would vanish — so it flips to white
/// there. A contrasting ring keeps it legible against either background.
struct SaveDot: ViewModifier {
    let show: Bool
    /// The host chip is currently accent-filled (selected), so draw the dot in white
    /// instead of accent — an accent dot on an accent fill is invisible.
    var onAccent: Bool = false
    /// The host clips its bounds (e.g. the segmented Flat/Round control), so the dot
    /// must sit INSIDE the corner rather than overhanging — an overhang gets clipped.
    var inset: Bool = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            Circle()
                .fill(onAccent ? Color.white : Color.accentColor)
                .frame(width: 9, height: 9)
                // A ring in the opposite tone so the dot reads on any background:
                // white core gets an accent hairline, accent core gets a white one.
                .overlay(
                    Circle()
                        .stroke(onAccent ? Color.accentColor.opacity(0.5) : .white, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 0.5)
                // On an overhang-safe chip, nudge onto its shoulder; on a clipping
                // host, tuck it just inside the corner so it isn't sliced off.
                .offset(x: inset ? -3 : 3, y: inset ? 3 : -3)
                // Scale/opacity (not `if show`) so the badge grows/shrinks with the
                // chip's own selection animation rather than fading on its own.
                .scaleEffect(show ? 1 : 0.1)
                .opacity(show ? 1 : 0)
                .animation(.snappy, value: show)
                .animation(.snappy, value: onAccent)
                .allowsHitTesting(false)
                // The chip's own a11y label already conveys the config; the dot is
                // a redundant visual cue, so it stays out of the a11y tree.
                .accessibilityHidden(true)
        }
    }
}

/// Speaks the save-dot's message: the dot itself is decorative (and a11y-hidden),
/// but "this path has a parked game" must reach VoiceOver too — as the chip's
/// VALUE, read after its label.
struct SaveValue: ViewModifier {
    let hasSave: Bool
    func body(content: Content) -> some View {
        content.accessibilityValue(
            hasSave ? Text("Game in progress", bundle: .module) : Text(verbatim: ""))
    }
}

/// Speaks a locked option's state + requirement as the control's a11y value
/// (the padlock badge itself is decorative and hidden).
struct LockValue: ViewModifier {
    let locked: Bool
    let requirement: UnlockEngine.Requirement?
    func body(content: Content) -> some View {
        if locked, let requirement {
            content.accessibilityValue(
                Text(
                    "Locked — \(UnlockGates.requirementText(requirement))",
                    bundle: .module))
        } else {
            content
        }
    }
}
