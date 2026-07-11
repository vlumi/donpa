import XCTest

@testable import DonpaCore

final class TopologyTests: XCTestCase {

    // MARK: BoundedSquareTopology

    func testBoundedNeighborCounts() {
        let t = BoundedSquareTopology(width: 5, height: 5)
        // Corner has 3 neighbours, edge has 5, interior has 8.
        XCTAssertEqual(t.neighbors(of: Coord(0, 0)).count, 3)
        XCTAssertEqual(t.neighbors(of: Coord(2, 0)).count, 5)
        XCTAssertEqual(t.neighbors(of: Coord(2, 2)).count, 8)
    }

    func testBoundedNormalizeRejectsOffBoard() {
        let t = BoundedSquareTopology(width: 3, height: 3)
        XCTAssertNil(t.normalize(Coord(-1, 0)))
        XCTAssertNil(t.normalize(Coord(3, 0)))
        XCTAssertEqual(t.normalize(Coord(2, 2)), Coord(2, 2))
    }

    func testBoundedAllCoordsCoversBoard() {
        let t = BoundedSquareTopology(width: 4, height: 3)
        let coords = Array(t.allCoords())
        XCTAssertEqual(coords.count, 12)
        XCTAssertEqual(Set(coords).count, 12)
    }

    // MARK: WrappedSquareTopology

    func testWrappedHasNoEdges() {
        let t = WrappedSquareTopology(width: 5, height: 5)
        // Every cell — including corners — has exactly 8 neighbours on a torus.
        for c in t.allCoords() {
            XCTAssertEqual(t.neighbors(of: c).count, 8, "cell \(c) should have 8 neighbours")
        }
    }

    func testWrappedNormalizeFolds() {
        let t = WrappedSquareTopology(width: 4, height: 4)
        XCTAssertEqual(t.normalize(Coord(-1, -1)), Coord(3, 3))
        XCTAssertEqual(t.normalize(Coord(4, 4)), Coord(0, 0))
        XCTAssertEqual(t.normalize(Coord(5, 2)), Coord(1, 2))
    }

    func testWrappedCornerWrapsToOppositeCorner() {
        let t = WrappedSquareTopology(width: 5, height: 5)
        let n = Set(t.neighbors(of: Coord(0, 0)))
        // Top-left's diagonal neighbour wraps to the bottom-right corner.
        XCTAssertTrue(n.contains(Coord(4, 4)))
    }

    // MARK: HexTopology

    func testHexInteriorHasSixNeighbours() {
        let t = HexTopology(width: 6, height: 6)
        // Interior cells on both row parities have exactly 6 neighbours.
        XCTAssertEqual(t.neighbors(of: Coord(2, 2)).count, 6)  // even row
        XCTAssertEqual(t.neighbors(of: Coord(2, 3)).count, 6)  // odd row
    }

    func testHexNeighboursMatchOddROffsets() {
        let t = HexTopology(width: 6, height: 6)
        // Even row (2,2): W/E plus the (-1,±1)/(0,±1) diagonals.
        XCTAssertEqual(
            Set(t.neighbors(of: Coord(2, 2))),
            [Coord(3, 2), Coord(1, 2), Coord(1, 3), Coord(2, 3), Coord(1, 1), Coord(2, 1)]
        )
        // Odd row (2,3): W/E plus the (0,±1)/(+1,±1) diagonals.
        XCTAssertEqual(
            Set(t.neighbors(of: Coord(2, 3))),
            [Coord(3, 3), Coord(1, 3), Coord(2, 4), Coord(3, 4), Coord(2, 2), Coord(3, 2)]
        )
    }

    func testHexAdjacencyIsSymmetric() {
        // If A is a neighbour of B, B must be a neighbour of A — else adjacency
        // counting (and the whole game) would be inconsistent.
        let t = HexTopology(width: 7, height: 7)
        for a in t.allCoords() {
            for b in t.neighbors(of: a) {
                XCTAssertTrue(
                    t.neighbors(of: b).contains(a),
                    "adjacency must be symmetric: \(a)↔\(b)")
            }
        }
    }

    func testHexEdgeAndCornerHaveFewerNeighbours() {
        let t = HexTopology(width: 5, height: 5)
        // A bounded hex board still has reduced-degree edges and corners.
        XCTAssertLessThan(t.neighbors(of: Coord(0, 0)).count, 6)
        XCTAssertLessThan(t.neighbors(of: Coord(2, 0)).count, 6)
    }

    func testHexNormalizeRejectsOffBoard() {
        let t = HexTopology(width: 3, height: 3)
        XCTAssertNil(t.normalize(Coord(-1, 0)))
        XCTAssertNil(t.normalize(Coord(3, 0)))
        XCTAssertEqual(t.normalize(Coord(2, 2)), Coord(2, 2))
    }

    // MARK: WrappedHexTopology

    func testWrappedHexHasNoEdges() {
        // Every cell — corners included — has exactly 6 neighbours on a hex torus.
        let t = WrappedHexTopology(width: 8, height: 8)
        for c in t.allCoords() {
            XCTAssertEqual(t.neighbors(of: c).count, 6, "cell \(c) should have 6 neighbours")
        }
    }

    func testWrappedHexAdjacencyIsSymmetric() {
        // The whole reason a hex torus needs even height: A→B must imply B→A across
        // the wrap seams too, or adjacency counting breaks. Even height makes it hold.
        let t = WrappedHexTopology(width: 8, height: 8)
        for a in t.allCoords() {
            for b in t.neighbors(of: a) {
                XCTAssertTrue(
                    t.neighbors(of: b).contains(a),
                    "wrapped-hex adjacency must be symmetric: \(a)↔\(b)")
            }
        }
    }

    func testWrappedHexNormalizeFolds() {
        let t = WrappedHexTopology(width: 8, height: 8)
        XCTAssertEqual(t.normalize(Coord(-1, -1)), Coord(7, 7))
        XCTAssertEqual(t.normalize(Coord(8, 8)), Coord(0, 0))
        XCTAssertEqual(t.normalize(Coord(10, 3)), Coord(2, 3))
    }
}

// MARK: Cursor stepping (Topology.stepped)

extension TopologyTests {
    /// Bounded boards clamp: a step off the edge returns nil (the cursor stays).
    func testSteppedClampsAtBoundedEdges() {
        let t = BoundedSquareTopology(width: 3, height: 3)
        XCTAssertNil(t.stepped(Coord(0, 0), dx: -1, dy: 0))
        XCTAssertNil(t.stepped(Coord(0, 0), dx: 0, dy: -1))
        XCTAssertNil(t.stepped(Coord(2, 2), dx: 1, dy: 0))
        XCTAssertEqual(t.stepped(Coord(1, 1), dx: 1, dy: 0), Coord(2, 1))
    }

    /// Wrapped boards fold: a step off the edge lands on the opposite side.
    func testSteppedWrapsAcrossTheSeam() {
        let t = WrappedSquareTopology(width: 4, height: 4)
        XCTAssertEqual(t.stepped(Coord(0, 0), dx: -1, dy: 0), Coord(3, 0))
        XCTAssertEqual(t.stepped(Coord(3, 3), dx: 1, dy: 1), Coord(0, 0))
    }

    /// On hex (odd-r), a vertical step is ALWAYS a true neighbour — the cursor's
    /// up/down zigzags around a straight line instead of drifting, both parities.
    func testSteppedVerticalIsAlwaysAHexNeighbour() {
        let t = HexTopology(width: 6, height: 6)
        for y in 1..<5 {
            for x in 1..<5 {
                let c = Coord(x, y)
                for dy in [-1, 1] {
                    let stepped = t.stepped(c, dx: 0, dy: dy)
                    XCTAssertNotNil(stepped)
                    XCTAssertTrue(
                        t.neighbors(of: c).contains(stepped!),
                        "stepping (0,\(dy)) from \(c) must land on a neighbour")
                }
            }
        }
    }

    /// Wrapped hex: vertical steps stay neighbours across the seam too.
    func testSteppedVerticalWrappedHexStaysNeighbour() {
        let t = WrappedHexTopology(width: 4, height: 4)
        for x in 0..<4 {
            let top = Coord(x, 0)
            let stepped = t.stepped(top, dx: 0, dy: -1)
            XCTAssertNotNil(stepped)
            XCTAssertTrue(
                t.neighbors(of: top).contains(stepped!),
                "seam step from \(top) must land on a neighbour")
        }
    }
}
