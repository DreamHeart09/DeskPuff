import XCTest
@testable import DeskPuffCore

final class DeskPuffCoreTests: XCTestCase {
    func testCompleteCycleAndDuplicateEvents() {
        var model = ToyModel()
        XCTAssertFalse(model.send(.light))
        XCTAssertTrue(model.send(.openBox)); XCTAssertFalse(model.send(.openBox))
        XCTAssertTrue(model.send(.takeCigarette)); XCTAssertTrue(model.send(.light))
        XCTAssertTrue(model.send(.beginInhale)); XCTAssertTrue(model.send(.endInhale))
        XCTAssertEqual(model.puffCount, 1); XCTAssertTrue(model.send(.extinguish))
        XCTAssertTrue(model.send(.reset)); XCTAssertEqual(model.state, .closed)
    }
    func testCancelDoesNotPuff() {
        var model = ToyModel()
        _ = model.send(.openBox); _ = model.send(.takeCigarette); _ = model.send(.light); _ = model.send(.beginInhale)
        XCTAssertTrue(model.send(.cancel)); XCTAssertEqual(model.state, .burning); XCTAssertEqual(model.puffCount, 0)
    }
    func testMouseVelocityClampingAndInvalidTime() {
        let sample = MotionSample(dx: 1000, dy: 0, dt: 0.01)
        XCTAssertEqual(sample.velocityX, 1800, accuracy: 0.01)
        XCTAssertEqual(MotionSample(dx: 10, dy: 10, dt: 1).velocityX, 0)
    }
}

extension DeskPuffCoreTests {
    func testCigaretteStyleManifestRoundTripsAndValidates() throws {
        let source = CigaretteStyleManifest(
            id: "community-slim", name: "社区细支", diameterMM: 6.2,
            paper: CigarettePaperProfile(color: "#F7F6F0", highlight: "#FFFFFF", shade: "#D8D9D5"),
            filter: CigaretteFilterProfile(color: "#C59A61", highlight: "#E6C88D", shade: "#8C6036", band: "#A17849"),
            smoke: CigaretteSmokeProfile(emissionMultiplier: 0.72, colorMode: .custom, color: "#CFD5D8")
        )
        XCTAssertNil(source.validationError())
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(CigaretteStyleManifest.self, from: data)
        XCTAssertEqual(decoded, source)
    }

    func testCigaretteStyleManifestRejectsUnsafeRangesAndColors() {
        var style = CigaretteStyleManifest(id: "slim", name: "细支", diameterMM: 4.8)
        XCTAssertNotNil(style.validationError())
        style.diameterMM = 7.8
        style.smoke.emissionMultiplier = 5
        XCTAssertNotNil(style.validationError())
        style.smoke.emissionMultiplier = 1
        style.filter.color = "red"
        XCTAssertNotNil(style.validationError())
    }
}

extension DeskPuffCoreTests {
    func testSmokeAmountsAreOrderedAndStandardPreservesBaseline() {
        XCTAssertLessThan(SmokeAmount.light.multiplier, SmokeAmount.standard.multiplier)
        XCTAssertEqual(SmokeAmount.standard.multiplier, 1)
        XCTAssertGreaterThan(SmokeAmount.heavy.multiplier, SmokeAmount.standard.multiplier)
    }
}

extension DeskPuffCoreTests {
    func testFilterGestureTapDragHoldAndCancel() {
        var gesture = FilterGesture()
        gesture.begin(); XCTAssertFalse(gesture.move(distance: 3)); XCTAssertEqual(gesture.end(), .tap)
        gesture.begin(); XCTAssertTrue(gesture.move(distance: 8)); XCTAssertFalse(gesture.hold()); XCTAssertEqual(gesture.end(), .dragFinished)
        gesture.begin(); XCTAssertTrue(gesture.hold()); XCTAssertFalse(gesture.move(distance: 20)); XCTAssertEqual(gesture.end(), .puff)
        gesture.begin(); _ = gesture.hold(); gesture.cancel(); XCTAssertEqual(gesture.end(), .none)
    }
}

extension DeskPuffCoreTests {
    func testBurnProgressAshAndInhale() {
        var normal = CigaretteBurn(); var inhaled = CigaretteBurn()
        normal.advance(seconds: 48, inhaling: false)
        inhaled.advance(seconds: 48, inhaling: true)
        XCTAssertEqual(normal.progress, 0.1, accuracy: 0.00001)
        XCTAssertEqual(inhaled.progress, 1, accuracy: 0.00001)
        var quadruple = CigaretteBurn(); quadruple.advance(seconds: 48, inhaling: true, inhaleMultiplier: 4)
        XCTAssertEqual(quadruple.progress, normal.progress * 4, accuracy: 0.00001)
        XCTAssertGreaterThan(normal.shedAsh(), 0)
        normal.advance(seconds: 1000, inhaling: false)
        XCTAssertEqual(normal.progress, 1, accuracy: 0.00001)
        XCTAssertTrue(normal.isFinished)
    }
    func testAshFallsWhenSupportingWindowMoves() {
        var particle = AshParticle(x: 60, y: 110, vx: 0, vy: -100, size: 2)
        let edge = AshSurface(id: 9, x: 0, y: 100, width: 200)
        particle.step(dt: 0.1, surfaces: [edge], floor: 0)
        XCTAssertGreaterThan(particle.vy, 0)
        for _ in 0..<20 where particle.support == nil { particle.step(dt: 0.02, surfaces: [edge], floor: 0) }
        XCTAssertEqual(particle.support, 9)
        let moved = AshSurface(id: 9, x: 30, y: 100, width: 200)
        let lower = AshSurface(id: 10, x: 0, y: 70, width: 200)
        particle.step(dt: 0.02, surfaces: [moved, lower], floor: 0)
        XCTAssertNil(particle.support); XCTAssertLessThan(particle.y, 101)
        XCTAssertGreaterThan(particle.vx, 0)
        for _ in 0..<100 where particle.support == nil { particle.step(dt: 0.02, surfaces: [moved, lower], floor: 0) }
        XCTAssertEqual(particle.support, 10); XCTAssertEqual(particle.y, 71, accuracy: 0.001)
    }
}

extension DeskPuffCoreTests {
    func testAshThreeLevelsAndFullShed() {
        XCTAssertEqual(AshAmount.allCases.count, 3)
        XCTAssertEqual(AshAmount.light.multiplier, 3)
        XCTAssertLessThan(AshAmount.light.multiplier, AshAmount.standard.multiplier)
        XCTAssertEqual(AshAmount.heavy.multiplier, AshAmount.standard.multiplier * 5)
        var burn = CigaretteBurn(); burn.advance(seconds: 48, inhaling: false)
        let before = burn.ash
        XCTAssertEqual(burn.shedAsh(all: true), before, accuracy: 0.00001)
        XCTAssertEqual(burn.ash, 0, accuracy: 0.00001)
        var tiny = CigaretteBurn(); tiny.advance(seconds: 1, inhaling: false)
        let tinyAmount = tiny.ash
        XCTAssertEqual(tiny.shedAsh(all: true), 0)
        XCTAssertEqual(tiny.ash, tinyAmount, accuracy: 0.00001)
        XCTAssertEqual(AshAmount.standard.particleCount(for: 0), 0)
        XCTAssertLessThan(AshAmount.standard.particleCount(for: 0.1), AshAmount.standard.particleCount(for: 0.8))
    }
    func testFiveTenAndTwentyTimesBurn() {
        for speed in [5.0, 10.0, 20.0] {
            var burn = CigaretteBurn(); burn.advance(seconds: 12, inhaling: true, inhaleMultiplier: speed)
            XCTAssertEqual(burn.progress, 12 * speed / CigaretteBurn.idleDuration, accuracy: 0.00001)
        }
    }
    func testPileFallsWhenSupportingWindowMoves() {
        let edge = AshSurface(id: 9, x: 0, y: 100, width: 200)
        var base = AshParticle(x: 60, y: 110, vx: 0, vy: -100, size: 3)
        for _ in 0..<100 where base.support == nil { base.step(dt: 0.02, surfaces: [edge], floor: 0) }
        XCTAssertEqual(base.support, 9)
        var top = AshParticle(x: 60, y: 120, vx: 0, vy: -100, size: 3)
        top.rest(on: base)
        XCTAssertEqual(top.support, 9); XCTAssertGreaterThan(top.y, base.y)
        top.step(dt: 0.02, surfaces: [AshSurface(id: 9, x: 20, y: 100, width: 200)], floor: 0)
        XCTAssertNil(top.support); XCTAssertLessThan(top.vy, 0)
    }
}

extension DeskPuffCoreTests {
    func testAshCanBounceOnRepeatedWindowMoves() {
        let first = AshSurface(id: 1, x: 0, y: 150, width: 200)
        let second = AshSurface(id: 2, x: 0, y: 80, width: 200)
        var p = AshParticle(x: 60, y: 180, vx: 0, vy: -100, size: 2)
        for _ in 0..<100 where p.support == nil { p.step(dt: 0.02, surfaces: [first, second], floor: 0) }
        XCTAssertEqual(p.support, 1)
        let moved = AshSurface(id: 1, x: 40, y: 150, width: 200)
        p.step(dt: 0.02, surfaces: [moved, second], floor: 0)
        XCTAssertNil(p.support); XCTAssertEqual(p.bounces, 0)
        for _ in 0..<100 where p.support == nil { p.step(dt: 0.02, surfaces: [moved, second], floor: 0) }
        XCTAssertEqual(p.support, 2)
        p.step(dt: 0.02, surfaces: [moved, AshSurface(id: 2, x: 40, y: 80, width: 200)], floor: 0)
        XCTAssertNil(p.support); XCTAssertEqual(p.bounces, 0); XCTAssertLessThan(p.vy, 0)
    }
    func testDockEstimateDoesNotCoverWholeScreen() {
        let dock = DockFootprint.horizontal(screenX: 0, screenWidth: 3440, tileSize: 37, itemCount: 44, pinning: "middle")!
        XCTAssertGreaterThan(dock.x, 0)
        XCTAssertLessThan(dock.x + dock.width, 3440)
        XCTAssertNil(DockFootprint.horizontal(screenX: 0, screenWidth: 3440, tileSize: 0, itemCount: 44, pinning: "middle"))
    }
}

extension DeskPuffCoreTests {
    func testDoubleTapRequiresCompletedTap() {
        var sequence = TapSequence()
        XCTAssertFalse(sequence.begin(clickCount: 2, time: 10, interval: 0.5))
        sequence.completedTap(time: 10)
        XCTAssertTrue(sequence.begin(clickCount: 2, time: 10.2, interval: 0.5))
        XCTAssertFalse(sequence.begin(clickCount: 2, time: 10.3, interval: 0.5))
        sequence.completedTap(time: 11); sequence.reset()
        XCTAssertFalse(sequence.begin(clickCount: 2, time: 11.1, interval: 0.5))
        sequence.completedTap(time: 12)
        XCTAssertFalse(sequence.begin(clickCount: 2, time: 13, interval: 0.5))
    }
}

extension DeskPuffCoreTests {
    func testAutomaticAshFallsOnlyWhenFull() {
        var burn = CigaretteBurn()
        burn.advance(seconds: 48, inhaling: false)
        XCTAssertEqual(burn.shedAshIfFull(), 0)
        burn.advance(seconds: 112, inhaling: false)
        XCTAssertEqual(burn.shedAshIfFull(), 1, accuracy: 0.00001)
        XCTAssertEqual(burn.ash, 0, accuracy: 0.00001)
        XCTAssertEqual(burn.shedAshIfFull(), 0)
    }
    func testSmokeDissipationDurations() {
        XCTAssertEqual(SmokeDissipation.normal.opacity(after: 0), 1)
        XCTAssertEqual(SmokeDissipation.normal.opacity(after: 90), 0.5, accuracy: 0.00001)
        XCTAssertEqual(SmokeDissipation.normal.opacity(after: 180), 0)
        XCTAssertEqual(SmokeDissipation.fast.opacity(after: 60), 0)
        XCTAssertEqual(SmokeDissipation.slow.opacity(after: 360), 0)
        XCTAssertEqual(SmokeDissipation.never.opacity(after: 100000), 1)
        XCTAssertEqual(SmokeDissipation.noAccumulation.opacity(after: 30), 0)
    }
}

extension DeskPuffCoreTests {
    func testWindowMotionGivesAshDirectionalDrift() {
        let surface = AshSurface(id: 20, x: 0, y: 100, width: 200)
        var particle = AshParticle(x: 60, y: 110, vx: 0, vy: -100, size: 3, shapeSeed: 50)
        for _ in 0..<100 where particle.support == nil { particle.step(dt: 0.02, surfaces: [surface], floor: 0) }
        XCTAssertEqual(particle.support, 20)
        particle.step(dt: 0.02, surfaces: [AshSurface(id: 20, x: 30, y: 100, width: 200)], floor: 0)
        XCTAssertNil(particle.support); XCTAssertGreaterThan(particle.vx, 0)
        XCTAssertLessThan(particle.vy, 0); XCTAssertNotEqual(particle.spin, 0)
    }
    func testAshPaletteIsDarkAndVaried() {
        XCTAssertGreaterThan(AshAppearance.shade(seed: 1), 0.1)
        XCTAssertLessThan(AshAppearance.shade(seed: 1), 0.4)
        XCTAssertNotEqual(AshAppearance.shade(seed: 1), AshAppearance.shade(seed: 2))
    }
}

extension DeskPuffCoreTests {
    func testDislodgedAshFallsPromptlyAndParticleCountStaysConstant() {
        let window = AshSurface(id: 30, x: 0, y: 700, width: 400)
        var pieces = (0..<12).map { index in
            AshParticle(x: 60 + Double(index), y: 715, vx: 0, vy: -100, size: 3, shapeSeed: UInt32(index + 1))
        }
        for _ in 0..<100 {
            for i in pieces.indices where pieces[i].support == nil { pieces[i].step(dt: 0.02, surfaces: [window], floor: 0) }
        }
        XCTAssertTrue(pieces.allSatisfy { $0.support == 30 })
        let moved = AshSurface(id: 30, x: 30, y: 700, width: 400)
        let count = pieces.count
        for _ in 0..<25 { for i in pieces.indices { pieces[i].step(dt: 0.02, surfaces: [moved], floor: 0) } }
        XCTAssertEqual(pieces.count, count)
        XCTAssertTrue(pieces.allSatisfy { $0.y < 650 })
    }
}

extension DeskPuffCoreTests {
    func testAshCapGrowsUntilShed() {
        var burn = CigaretteBurn()
        burn.advance(seconds: 40, inhaling: false)
        let first = AshGeometry.capLength(level: burn.ash)
        burn.advance(seconds: 40, inhaling: false)
        let second = AshGeometry.capLength(level: burn.ash)
        XCTAssertGreaterThan(first, 0); XCTAssertGreaterThan(second, first)
        _ = burn.shedAsh(all: true)
        XCTAssertEqual(AshGeometry.capLength(level: burn.ash), 0)
    }
    func testLargeBurstNearFloorFormsPileWithoutLosingParticles() {
        var particles: [AshParticle] = []
        for frame in 0..<240 {
            if frame < 10 {
                for j in 0..<12 {
                    let n = frame * 12 + j
                    var p = AshParticle(x: Double((n * 17) % 29 - 14), y: 9 + Double((n * 31) % 19), vx: Double((n * 23) % 111 - 55), vy: Double((n * 11) % 40 - 20), size: 3 + Double(n % 4), shapeSeed: UInt32(n + 1))
                    p.pileSpread = 1; particles.append(p)
                }
            }
            let old = particles.map { $0.y - $0.size / 2 }
            for i in particles.indices { particles[i].step(dt: 1.0/30, surfaces: [], floor: 0) }
            let settled = particles.map { $0.restingOnPile || ($0.vy == 0 && $0.y - $0.size / 2 <= 0.5) }
            AshPileSolver.resolve(&particles, oldBottoms: old, settled: settled)
        }
        XCTAssertEqual(particles.count, 120)
        XCTAssertGreaterThan(particles.filter(\.restingOnPile).count, 10)
        XCTAssertGreaterThan(particles.map(\.y).max() ?? 0, 8)
        XCTAssertGreaterThan((particles.map(\.x).max() ?? 0) - (particles.map(\.x).min() ?? 0), 20)
    }
    func testAshReleasedInsideFloorDoesNotJumpUpToPile() {
        var base = AshParticle(x: 0, y: 2, vx: 0, vy: 0, size: 4)
        var falling = AshParticle(x: 0, y: 0, vx: 0, vy: -10, size: 4, shapeSeed: 2)
        falling.pileSpread = 1
        let old = [base.y - base.size / 2, falling.y - falling.size / 2]
        base.step(dt: 1.0 / 30, surfaces: [], floor: 0)
        falling.step(dt: 1.0 / 30, surfaces: [], floor: 0)
        var particles = [base, falling]
        AshPileSolver.resolve(&particles, oldBottoms: old, settled: [true, true])
        XCTAssertFalse(particles[1].restingOnPile)
        XCTAssertEqual(particles[1].y, particles[0].y, accuracy: 0.00001)
    }

    func testWindowReleaseSpreadsImmediatelyWithoutExcessiveImpulse() {
        let window = AshSurface(id: 45, x: 0, y: 100, width: 300)
        let moved = AshSurface(id: 45, x: 100, y: 100, width: 300)
        var pieces = [1, 50, 100].map { seed in
            AshParticle(x: 100, y: 105, vx: 0, vy: -40, size: 3, shapeSeed: UInt32(seed))
        }
        for _ in 0..<100 { for i in pieces.indices where pieces[i].support == nil {
            pieces[i].step(dt: 0.02, surfaces: [window], floor: 0)
        } }
        XCTAssertTrue(pieces.allSatisfy { $0.support == window.id })
        for i in pieces.indices { pieces[i].step(dt: 1.0 / 30, surfaces: [moved], floor: 0) }
        XCTAssertLessThan(pieces[0].x, pieces[2].x)
        XCTAssertGreaterThan(pieces[2].x - pieces[0].x, 1)
        XCTAssertTrue(pieces.allSatisfy { abs($0.vx) <= 40 })
    }

    func testFallingAshEmberCoolsEvenWhenSettled() {
        var particle = AshParticle(x: 0, y: 2, vx: 0, vy: 0, size: 4)
        particle.emberRemaining = 0.5
        particle.step(dt: 0.2, surfaces: [], floor: 0)
        XCTAssertEqual(particle.emberRemaining, 0.3, accuracy: 0.00001)
        particle.step(dt: 0.4, surfaces: [], floor: 0)
        XCTAssertEqual(particle.emberRemaining, 0)
    }

    func testPuffRespondsToInhaleConsumptionAndFadesSmoothly() {
        var profiles: [PuffProfile] = []
        for speed in [5.0, 10.0, 20.0] {
            var burn = CigaretteBurn()
            burn.advance(seconds: 3, inhaling: true, inhaleMultiplier: speed)
            profiles.append(PuffProfile(consumedBurnSeconds: burn.progress * CigaretteBurn.idleDuration))
        }
        XCTAssertLessThan(profiles[0].duration, profiles[1].duration)
        XCTAssertLessThan(profiles[1].duration, profiles[2].duration)
        XCTAssertLessThan(profiles[0].intensity, profiles[1].intensity)
        XCTAssertLessThan(profiles[1].intensity, profiles[2].intensity)
        let puff = profiles[1]
        XCTAssertEqual(puff.envelope(at: 0), 0, accuracy: 0.00001)
        XCTAssertGreaterThan(puff.envelope(at: puff.duration / 2), 0)
        XCTAssertEqual(puff.envelope(at: puff.duration), 0)
        XCTAssertEqual(PuffProfile(consumedBurnSeconds: 1000).duration, PuffProfile(consumedBurnSeconds: 100).duration)
    }

    func testInhaleReservoirStopsAtCapacityForEachSpeed() {
        for speed in [5.0, 10.0, 20.0] {
            var reservoir = InhaleReservoir()
            let active = reservoir.take(seconds: 100, multiplier: speed)
            XCTAssertEqual(active, InhaleReservoir.capacity / speed, accuracy: 0.00001)
            XCTAssertEqual(reservoir.amount, InhaleReservoir.capacity, accuracy: 0.00001)
            XCTAssertTrue(reservoir.isFull)
            XCTAssertEqual(reservoir.take(seconds: 10, multiplier: speed), 0)
        }
        XCTAssertEqual(PuffProfile(consumedBurnSeconds: 0).intensity, 0)
        XCTAssertEqual(PuffProfile(consumedBurnSeconds: 60).intensity,
                       PuffProfile(consumedBurnSeconds: 1000).intensity)
    }

    func testPuffReleasesQuicklyAndSizeFollowsInhaledAmount() {
        let small = PuffProfile(consumedBurnSeconds: 10)
        let large = PuffProfile(consumedBurnSeconds: InhaleReservoir.capacity)
        XCTAssertGreaterThan(large.size, small.size)
        XCTAssertGreaterThan(large.envelope(at: 0.1), large.envelope(at: large.duration * 0.6))
        XCTAssertEqual(large.envelope(at: large.duration), 0)
        XCTAssertEqual(PuffProfile(consumedBurnSeconds: 0).envelope(at: 0.1), 0)
    }

    func testLargePuffSpreadsMoreWithoutIncreasingPeakDensity() {
        let small = PuffProfile(consumedBurnSeconds: 10)
        let full = PuffProfile(consumedBurnSeconds: 60)
        XCTAssertGreaterThan(full.size, small.size)
        XCTAssertLessThan(full.densityIntensity, small.densityIntensity)
        XCTAssertGreaterThan(full.densityIntensity * full.size * full.size * full.duration,
                             small.densityIntensity * small.size * small.size * small.duration)
    }

    func testSimultaneouslyLandingAshFormsPile() {
        var flakes = (0..<40).map { i -> AshParticle in
            var p = AshParticle(x: Double(i % 5) * 0.3, y: 6, vx: 0, vy: -100, size: 4, shapeSeed: UInt32(i + 1))
            p.pileSpread = 1
            return p
        }
        let old = flakes.map { $0.y - $0.size / 2 }
        for i in flakes.indices { flakes[i].step(dt: 1.0 / 30, surfaces: [], floor: 0) }
        AshPileSolver.resolve(&flakes, oldBottoms: old, settled: Array(repeating: true, count: flakes.count))
        XCTAssertEqual(flakes.count, 40)
        XCTAssertGreaterThan(flakes.map(\.y).max() ?? 0, 3.2)
    }
    func testHeavyAshIsReleasedWithinSixFramesWithoutDroppingFlakes() {
        let count = AshAmount.heavy.particleCount(for: 1)
        let batch = AshAmount.releaseBatchSize(for: count)
        XCTAssertEqual(count, 5 * AshAmount.standard.particleCount(for: 1))
        XCTAssertLessThanOrEqual((count + batch - 1) / batch, 6)
    }

    func testSettledAshCanPartiallyOverlapWithoutSinking() {
        let base = AshParticle(x: 0, y: 2, vx: 0, vy: 0, size: 4)
        var first = AshParticle(x: 0, y: 9, vx: 0, vy: -20, size: 4, shapeSeed: 1)
        var second = AshParticle(x: 0, y: 9, vx: 0, vy: -20, size: 4, shapeSeed: 89)
        first.pileSpread = 1; second.pileSpread = 1
        first.rest(on: base); second.rest(on: base)
        XCTAssertGreaterThan(first.y, base.y)
        XCTAssertLessThan(first.y, base.y + (base.size + first.size) / 2)
        XCTAssertGreaterThanOrEqual(first.y - first.size / 2, 0)
        XCTAssertNotEqual(first.y, second.y)
    }

    func testNaturalAshHasOnlyMinorCrumbs() {
        for level in AshAmount.allCases {
            XCTAssertGreaterThan(level.naturalCrumbCount(for: 1), 0)
            XCTAssertLessThan(level.naturalCrumbCount(for: 1), level.particleCount(for: 1) / 10)
            XCTAssertEqual(level.naturalCrumbCount(for: 0), 0)
        }
        XCTAssertGreaterThan(AshAmount.heavy.naturalCrumbCount(for: 1), AshAmount.standard.naturalCrumbCount(for: 1))
    }
    func testNaturalAshClumpStaysIntactOnWindowAndFallsWhenMoved() {
        let edge = AshSurface(id: 66, x: 0, y: 100, width: 200)
        var clump = AshParticle(x: 50, y: 160, vx: 0, vy: 0, size: 16)
        clump.isClump = true; clump.beginLooseFall()
        for _ in 0..<200 where clump.support == nil { clump.step(dt: 1.0 / 30, surfaces: [edge], floor: 0) }
        XCTAssertEqual(clump.support, 66)
        XCTAssertTrue(clump.isClump)
        clump.step(dt: 1.0 / 30, surfaces: [AshSurface(id: 66, x: 25, y: 100, width: 200)], floor: 0)
        XCTAssertNil(clump.support)
        XCTAssertTrue(clump.isClump)
    }

    func testDetachedAshMatchesCapAndDisplayScale() {
        let size = AshGeometry.detachedSize(level: 1, scale: 0.75)
        XCTAssertEqual(size.width, (AshGeometry.capLength(level: 1) + 3.5) * 0.75, accuracy: 0.0001)
        XCTAssertEqual(size.height, (26 - 11.7) * 0.85 * 0.75, accuracy: 0.0001)
        XCTAssertLessThan(AshGeometry.detachedSize(level: 0.25, scale: 0.75).width, size.width)
        let standard = AshGeometry.fragmentCount(level: 1, scale: 0.75, amount: .standard)
        XCTAssertEqual(AshGeometry.fragmentCount(level: 1, scale: 0.75, amount: .heavy), standard * 5)
        XCTAssertLessThan(AshGeometry.fragmentCount(level: 0.25, scale: 0.75, amount: .standard), standard)
        XCTAssertLessThan(AshGeometry.fragmentCount(level: 1, scale: 0.5, amount: .standard), standard)
    }

    func testCigaretteRotationCoordinatesAndHandles() {
        let tip = 33.0
        XCTAssertEqual(CigarettePose.rotationPivot(forX: tip, tip: tip), 180)
        XCTAssertEqual(CigarettePose.rotationPivot(forX: 180, tip: tip), tip)
        XCTAssertNil(CigarettePose.rotationPivot(forX: 100, tip: tip))
        let point = CGPoint(x: tip, y: 19)
        for angle in [0.0, Double.pi / 2, -Double.pi / 3, Double.pi] {
            let transformed = CigarettePose.canvasPoint(point, angle: angle)
            let original = CigarettePose.logicalPoint(transformed, angle: angle)
            XCTAssertEqual(original.x, point.x, accuracy: 0.00001)
            XCTAssertEqual(original.y, point.y, accuracy: 0.00001)
        }
    }

    func testClumpCollisionReleasesReservedCrumbsOnlyOnce() {
        var base = AshParticle(x: 0, y: 2, vx: 0, vy: 0, size: 4)
        var clump = AshParticle(x: 8, y: 9.5, vx: 0, vy: -50, size: 10)
        clump.isClump = true; clump.visualWidthScale = 2; clump.pileSpread = 0.4
        clump.pendingImpactCrumbs = 3
        let old = [base.y - base.size / 2, clump.y - clump.size / 2]
        base.step(dt: 1.0 / 30, surfaces: [], floor: 0)
        clump.step(dt: 1.0 / 30, surfaces: [], floor: 0)
        var particles = [base, clump]
        AshPileSolver.resolve(&particles, oldBottoms: old, settled: [true, false])
        XCTAssertTrue(particles[1].restingOnPile)
        XCTAssertEqual(particles[1].takeImpactCrumbs(previousBounces: 0, floor: 0), 3)
        XCTAssertGreaterThan(particles[1].emberRemaining, 0)
        XCTAssertEqual(particles[1].takeImpactCrumbs(previousBounces: 0, floor: 0), 0)
        XCTAssertTrue(particles[1].isClump)
    }

    func testRotationHandlesStayUsableAsCigaretteShortens() {
        for tip in [33.0, 100.0, 133.0] {
            XCTAssertEqual(CigarettePose.rotationPivot(forX: tip + 10, tip: tip), 180)
            XCTAssertEqual(CigarettePose.rotationPivot(forX: 170, tip: tip), tip)
            XCTAssertNil(CigarettePose.rotationPivot(forX: (tip + 180) / 2, tip: tip))
        }
        let shortTip = 133.0
        XCTAssertEqual(CigarettePose.rotationPivot(forX: shortTip + 13, tip: shortTip, screenScale: 0.5), 180)
        XCTAssertNil(CigarettePose.rotationPivot(forX: (shortTip + 180) / 2, tip: shortTip, screenScale: 0.5))
    }

    func testNaturalClumpImpactEmbersLastAboutOneMinute() {
        var clump = AshParticle(x: 0, y: 5, vx: 0, vy: 0, size: 10)
        clump.isClump = true; clump.pendingImpactCrumbs = 1
        XCTAssertEqual(clump.takeImpactCrumbs(previousBounces: 0, floor: 0), 1)
        XCTAssertEqual(clump.emberRemaining, 60, accuracy: 0.00001)
        for _ in 0..<59 { clump.step(dt: 1, surfaces: [], floor: 0) }
        XCTAssertGreaterThan(clump.emberRemaining, 0)
        clump.step(dt: 1, surfaces: [], floor: 0)
        XCTAssertEqual(clump.emberRemaining, 0, accuracy: 0.00001)
    }

    func testMultipleCigarettesHaveIndependentBurnAndInhaleState() {
        var first = CigaretteBurn(), second = CigaretteBurn()
        var firstInhale = InhaleReservoir(), secondInhale = InhaleReservoir()
        let active = firstInhale.take(seconds: 2, multiplier: 10)
        first.advance(seconds: active, inhaling: true, inhaleMultiplier: 10)
        second.advance(seconds: 2, inhaling: false)
        XCTAssertGreaterThan(first.progress, second.progress)
        XCTAssertGreaterThan(firstInhale.amount, 0)
        XCTAssertEqual(secondInhale.amount, 0)
        _ = secondInhale.take(seconds: 1, multiplier: 5)
        XCTAssertNotEqual(firstInhale.amount, secondInhale.amount)
        let preservedProgress = second.progress
        first = CigaretteBurn()
        XCTAssertEqual(first.progress, 0)
        XCTAssertEqual(second.progress, preservedProgress)
    }

    func testAshLandsOnCigaretteAndFallsWhenItMoves() {
        let edges = CigaretteAshSurface.segments(from: CGPoint(x: -60, y: 100), to: CGPoint(x: 60, y: 100), idBase: 0x40000100)
        XCTAssertEqual(edges.count, 12)
        XCTAssertEqual(Set(edges.map(\.id)).count, 12)
        var ash = AshParticle(x: 4, y: 130, vx: 0, vy: -40, size: 3)
        for _ in 0..<150 where ash.support == nil { ash.step(dt: 1.0 / 30, surfaces: edges, floor: 0) }
        XCTAssertNotNil(ash.support)
        let moved = CigaretteAshSurface.segments(from: CGPoint(x: -30, y: 100), to: CGPoint(x: 90, y: 100), idBase: 0x40000100)
        ash.step(dt: 1.0 / 30, surfaces: moved, floor: 0)
        XCTAssertNil(ash.support)
        XCTAssertLessThan(ash.vy, 0)
        let angled = CigaretteAshSurface.segments(from: CGPoint(x: -30, y: 50), to: CGPoint(x: 30, y: 110), idBase: 0x40000200)
        XCTAssertGreaterThan(angled.last!.y, angled.first!.y)
        XCTAssertTrue(angled.allSatisfy { $0.width > 0 })
    }

    func testCigaretteContactSeparatesTipFilterDockAndDisplaySeams() {
        let screen = CigaretteBoundary(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), usableTop: 770)
        let tip = CigaretteContact.resolve(tip: CGPoint(x: -8, y: 300), filter: CGPoint(x: 100, y: 300), previousTip: CGPoint(x: 5, y: 300), previousFilter: CGPoint(x: 110, y: 300), screens: [screen], obstacles: [])
        XCTAssertTrue(tip.tipContact); XCTAssertFalse(tip.filterContact); XCTAssertEqual(tip.correction.x, 8)
        let filter = CigaretteContact.resolve(tip: CGPoint(x: 400, y: 300), filter: CGPoint(x: 1007, y: 300), previousTip: CGPoint(x: 390, y: 300), previousFilter: CGPoint(x: 990, y: 300), screens: [screen], obstacles: [])
        XCTAssertFalse(filter.tipContact); XCTAssertTrue(filter.filterContact)
        let dock = CGRect(x: 400, y: 0, width: 200, height: 90)
        let dockHit = CigaretteContact.resolve(tip: CGPoint(x: 500, y: 75), filter: CGPoint(x: 650, y: 120), previousTip: CGPoint(x: 500, y: 100), previousFilter: CGPoint(x: 650, y: 140), screens: [screen], obstacles: [dock])
        XCTAssertTrue(dockHit.tipContact); XCTAssertEqual(dockHit.correction.y, 15)
        let other = CigaretteBoundary(frame: CGRect(x: 1000, y: 0, width: 1000, height: 800), usableTop: 770)
        let seam = CigaretteContact.resolve(tip: CGPoint(x: 1005, y: 300), filter: CGPoint(x: 900, y: 300), previousTip: CGPoint(x: 995, y: 300), previousFilter: CGPoint(x: 890, y: 300), screens: [screen, other], obstacles: [])
        XCTAssertFalse(seam.tipContact); XCTAssertFalse(seam.filterContact)
        let top = CigaretteContact.resolve(tip: CGPoint(x: 300, y: 780), filter: CGPoint(x: 400, y: 780), previousTip: CGPoint(x: 300, y: 750), previousFilter: CGPoint(x: 400, y: 750), screens: [screen], obstacles: [])
        XCTAssertEqual(top.correction.y, -10)
        let above = CigaretteBoundary(frame: CGRect(x: 0, y: 800, width: 1000, height: 800), usableTop: 1570)
        let vertical = CigaretteContact.resolve(tip: CGPoint(x: 300, y: 780), filter: CGPoint(x: 400, y: 700), previousTip: CGPoint(x: 300, y: 760), previousFilter: CGPoint(x: 400, y: 690), screens: [screen, above], obstacles: [])
        XCTAssertFalse(vertical.tipContact); XCTAssertFalse(vertical.filterContact)
    }

    func testCrushRespondsToSpeedAndRepeatedImpacts() {
        let gentle = CigaretteImpact.compression(current: 0, speed: 100, pressure: 0.2)
        let fast = CigaretteImpact.compression(current: 0, speed: 1000, pressure: 0.2)
        XCTAssertGreaterThan(fast, gentle)
        XCTAssertEqual(CigaretteImpact.compression(current: gentle, speed: 100, pressure: 0.2), gentle)
        XCTAssertLessThanOrEqual(CigaretteImpact.compression(current: 0.95, speed: 5000, pressure: 1), 0.78)
        XCTAssertGreaterThan(CigaretteImpact.charLevel(ash: 0), 0)
        XCTAssertGreaterThan(CigaretteImpact.fragmentLevel(ash: 0), 0)
        var burn = CigaretteBurn()
        burn.advance(seconds: 2, inhaling: false)
        let stored = burn.ash
        XCTAssertGreaterThan(stored, 0)
        XCTAssertEqual(burn.shedAshForCrush(), stored, accuracy: 0.000001)
        XCTAssertEqual(burn.ash, 0)
        XCTAssertEqual(burn.shedAshForCrush(), 0)
    }

    func testCigaretteWrinklesRemainLocalAndKeepRoundBody() {
        XCTAssertEqual(CigaretteImpact.wrinkleOffset(distance: 0, compression: 0), 0)
        XCTAssertEqual(CigaretteImpact.wrinkleOffset(distance: 24, compression: 1), 0)
        let offsets = (0...24).map { CigaretteImpact.wrinkleOffset(distance: Double($0), compression: 1) }
        XCTAssertTrue(offsets.contains { $0 > 0.1 })
        XCTAssertTrue(offsets.contains { $0 < -0.1 })
        for offset in offsets {
            let lower = 11 + offset, upper = 27 - offset
            XCTAssertEqual((lower + upper) / 2, 19, accuracy: 0.000001)
            XCTAssertGreaterThan(upper - lower, 13)
        }
    }

    func testCrushDamageIsAnchoredAndConsumedByBurning() {
        let anchor = 33.0
        let tipShift = CigaretteImpact.axialOffset(position: anchor, damageAt: anchor, pressure: 1)
        let middleShift = CigaretteImpact.axialOffset(position: anchor + 12, damageAt: anchor, pressure: 1)
        XCTAssertGreaterThan(tipShift, middleShift)
        XCTAssertEqual(CigaretteImpact.axialOffset(position: anchor + 24, damageAt: anchor, pressure: 1), 0)
        XCTAssertEqual(CigaretteImpact.axialOffset(position: anchor, damageAt: anchor, pressure: 0), 0)
        XCTAssertEqual(CigaretteImpact.wrinkleOffset(distance: -1, compression: 1), 0)
        XCTAssertFalse(CigaretteImpact.damageConsumed(tip: anchor + 23.9, damageAt: anchor))
        XCTAssertTrue(CigaretteImpact.damageConsumed(tip: anchor + 24, damageAt: anchor))
    }
    func testWholeCigaretteCannotTunnelBehindDock() {
        let screen = CigaretteBoundary(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), usableTop: 770)
        let dock = CGRect(x: 400, y: 0, width: 200, height: 90)
        let body = CigaretteContact.resolve(tip: CGPoint(x: 350, y: 80), filter: CGPoint(x: 650, y: 80), previousTip: CGPoint(x: 350, y: 110), previousFilter: CGPoint(x: 650, y: 110), screens: [screen], obstacles: [dock])
        XCTAssertGreaterThan(body.correction.y, 0)
        XCTAssertFalse(body.tipContact); XCTAssertFalse(body.filterContact)
        let fast = CigaretteContact.resolve(tip: CGPoint(x: 500, y: 20), filter: CGPoint(x: 700, y: 120), previousTip: CGPoint(x: 500, y: 110), previousFilter: CGPoint(x: 700, y: 140), screens: [screen], obstacles: [dock])
        XCTAssertTrue(fast.tipContact); XCTAssertGreaterThan(fast.correction.y, 0)
        let away = CigaretteContact.resolve(tip: CGPoint(x: 500, y: 120), filter: CGPoint(x: 650, y: 120), previousTip: CGPoint(x: 500, y: 90), previousFilter: CGPoint(x: 650, y: 120), screens: [screen], obstacles: [dock])
        XCTAssertEqual(away.correction, .zero); XCTAssertFalse(away.tipContact)
    }

    func testPressureRespondsAndRecoversWithoutChangingPermanentDamage() {
        let pressed = CigaretteImpact.pressureAfter(current: 0, target: 1, elapsed: 0.08)
        XCTAssertGreaterThan(pressed, 0); XCTAssertLessThan(pressed, 1)
        let recovered = CigaretteImpact.pressureAfter(current: pressed, target: 0, elapsed: 0.08)
        XCTAssertGreaterThan(recovered, 0); XCTAssertLessThan(recovered, pressed)
        let anchor = 33.0
        XCTAssertGreaterThan(CigaretteImpact.axialOffset(position: anchor, damageAt: anchor, pressure: pressed),
                             CigaretteImpact.axialOffset(position: anchor, damageAt: anchor, pressure: recovered))
        XCTAssertNotEqual(CigaretteImpact.wrinkleOffset(distance: 4, compression: 0.5), 0)
    }
    func testCrushAshHasBoundedSizeAndCountVariation() {
        let small = AshCrushProfile(ash: 0.5, baseCount: 20, impact: 0, charSample: 0, sizeSample: 0, countSample: 0)
        let large = AshCrushProfile(ash: 0.5, baseCount: 20, impact: 0, charSample: 1, sizeSample: 1, countSample: 1)
        XCTAssertGreaterThan(large.charLevel, small.charLevel)
        XCTAssertGreaterThan(large.sizeVariation, small.sizeVariation)
        XCTAssertGreaterThan(large.fragmentCount, small.fragmentCount)
        let hard = AshCrushProfile(ash: 0.5, baseCount: 20, impact: 1, charSample: 0.5, sizeSample: 0.5, countSample: 0.5)
        let soft = AshCrushProfile(ash: 0.5, baseCount: 20, impact: 0, charSample: 0.5, sizeSample: 0.5, countSample: 0.5)
        XCTAssertGreaterThan(hard.fragmentCount, soft.fragmentCount)
    }

    func testLocalizedFoldKeepsUndamagedSideStraightAndRoundTrips() {
        let hinge = 45.0
        let angle = CigaretteImpact.foldAngle(compression: 0.65, pressure: 0.4, direction: 1)
        XCTAssertGreaterThan(angle, 0)
        let fixed = CGPoint(x: 100, y: 19)
        XCTAssertEqual(CigaretteImpact.foldPoint(fixed, hingeX: hinge, angle: angle), fixed)
        for point in [CGPoint(x: 33, y: 19), CGPoint(x: 32, y: 12), CGPoint(x: 35, y: 26)] {
            let folded = CigaretteImpact.foldPoint(point, hingeX: hinge, angle: angle)
            let restored = CigaretteImpact.unfoldPoint(folded, hingeX: hinge, angle: angle)
            XCTAssertEqual(restored.x, point.x, accuracy: 0.00001)
            XCTAssertEqual(restored.y, point.y, accuracy: 0.00001)
            XCTAssertEqual(hypot(folded.x - hinge, folded.y - 19), hypot(point.x - hinge, point.y - 19), accuracy: 0.00001)
        }
        XCTAssertEqual(CigaretteImpact.foldAngle(compression: 0, pressure: 1, direction: 1), 0)
    }
    func testDockIsRaisedFloorEvenWhenAlreadyInsideOrBeyondScreen() {
        let screen = CigaretteBoundary(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), usableTop: 770)
        let dock = CGRect(x: 400, y: 0, width: 200, height: 90)
        let inside = CigaretteContact.resolve(tip: CGPoint(x: 500, y: 50), filter: CGPoint(x: 550, y: 50), previousTip: CGPoint(x: 500, y: 60), previousFilter: CGPoint(x: 550, y: 60), screens: [screen], obstacles: [dock])
        XCTAssertEqual(inside.correction.y, 40)
        let through = CigaretteContact.resolve(tip: CGPoint(x: 500, y: -30), filter: CGPoint(x: 650, y: 100), previousTip: CGPoint(x: 500, y: 110), previousFilter: CGPoint(x: 650, y: 130), screens: [screen], obstacles: [dock])
        XCTAssertGreaterThanOrEqual(through.correction.y, 120)
        XCTAssertTrue(through.tipContact)
        let side = CigaretteContact.resolve(tip: CGPoint(x: 100, y: -8), filter: CGPoint(x: 200, y: 40), previousTip: CGPoint(x: 100, y: 10), previousFilter: CGPoint(x: 200, y: 45), screens: [screen], obstacles: [dock])
        XCTAssertEqual(side.correction.y, 8)
    }

}

extension DeskPuffCoreTests {
    func testFlameWindDirectionAndDampedRecovery() {
        var flame = FlameDynamics()
        for _ in 0..<60 { flame.advance(dt: 1.0 / 60, air: CGPoint(x: -450, y: 0), level: 0.5) }
        XCTAssertLessThan(flame.bend, -5)
        let displaced = abs(flame.bend)
        for _ in 0..<120 { flame.advance(dt: 1.0 / 60, air: .zero, level: 0.5) }
        XCTAssertLessThan(abs(flame.bend), displaced * 0.05)
    }

    func testFlameSweptMouseDistanceAndBoundedInput() {
        XCTAssertEqual(FlameDynamics.distanceToSegment(CGPoint(x: 0, y: 5), from: CGPoint(x: -10, y: 0), to: CGPoint(x: 10, y: 0)), 5, accuracy: 0.001)
        var flame = FlameDynamics()
        for _ in 0..<300 { flame.advance(dt: 0.1, air: CGPoint(x: 100_000, y: -100_000), level: 1) }
        XCTAssertTrue(flame.bend.isFinite)
        XCTAssertLessThanOrEqual(abs(flame.bend), 220.1)
        XCTAssertGreaterThanOrEqual(flame.verticalFlow, -1)
    }
}

extension DeskPuffCoreTests {
    func testFlameFieldHeightAndContinuousWindDeformation() {
        let low = FlameField.height(level: 0), medium = FlameField.height(level: 0.5), high = FlameField.height(level: 1)
        XCTAssertEqual(low / medium, 0.55, accuracy: 0.02)
        XCTAssertEqual(high / medium, 1.86, accuracy: 0.02)
        XCTAssertEqual(FlameField.center(height: 0, time: 2, bend: 20, level: 1), 0, accuracy: 0.001)
        XCTAssertGreaterThan(FlameField.center(height: 1, time: 2, bend: 20, level: 1),
                             FlameField.center(height: 1, time: 2, bend: -20, level: 1) + 30)
        let a = FlameField.bitmap(width: 64, height: 96, level: 1, time: 1, bend: 0)
        let b = FlameField.bitmap(width: 64, height: 96, level: 1, time: 2, bend: 0)
        XCTAssertEqual(a.count, 64 * 96 * 4)
        XCTAssertNotEqual(a, b)
    }
}
