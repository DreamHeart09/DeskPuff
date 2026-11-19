import AppKit
import MetalKit
import DeskPuffCore

private struct SmokeParameters {
    var dt: Float = 0
    var source = SIMD2<Float>(0.5, 0.8)
    var mouse = SIMD2<Float>(-1, -1)
    var previousMouse = SIMD2<Float>(-1, -1)
    var wind = SIMD2<Float>(0, 0)
    var emission: Float = 0
    var time: Float = 0
    var aspect: Float = 1
    var sourceRadius: Float = 0.01
    var opacity: Float = 1
    var accumulation: Float = 1
    var puffSource = SIMD2<Float>(0.5, 0.8)
    var puffEmission: Float = 0
    var inhale: Float = 0
    var puffSize: Float = 1
    var previousSource = SIMD2<Float>(0.5, 0.8)
    var sourceWind = SIMD2<Float>(0, 0)
    var cloudVariation: Float = 0
    var colorTint = SIMD4<Float>(1, 1, 1, 0)
    var sootSource = SIMD2<Float>(0.5, 0.8)
    var previousSootSource = SIMD2<Float>(0.5, 0.8)
    var sootEmission: Float = 0
    var sootRadius: Float = 0.015
}

final class SmokeView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let compute: MTLComputePipelineState
    private let rebasePipeline: MTLComputePipelineState
    private let render: MTLRenderPipelineState
    private var fields: [MTLTexture] = []
    private var sootFields: [MTLTexture] = []
    private var current = 0
    private var sootCurrent = 0
    private var lastTime: CFTimeInterval = 0
    private var lastMouse: NSPoint?
    private var lastSource: NSPoint?
    private var startTime = CACurrentMediaTime()
    private var burstUntil: CFTimeInterval = 0
    private var burstStarted: CFTimeInterval = 0
    private var burstProfile = PuffProfile(consumedBurnSeconds: 0)
    private var burstScreenPoint = NSPoint.zero
    private var lastSootSource: NSPoint?
    private var sootTailUntil: CFTimeInterval = 0
    private var stoppedAt: CFTimeInterval?
    private var hiddenAt: CFTimeInterval?
    private var hasSmoke = false
    var emits = true {
        didSet {
            guard emits != oldValue else { return }
            lastSource = nil
            if emits && burning { resume() }
            else if !emits && !hasSmoke && sootEmission <= 0 && CACurrentMediaTime() >= sootTailUntil { isPaused = true }
        }
    }
    var inhaling = false
    var cloudVariation = false
    var colorTint = SIMD4<Float>(1, 1, 1, 0)
    var sootSourceInWindow = NSPoint(x: 300, y: 100)
    var sootEmission: Float = 0 {
        didSet {
            guard sootEmission != oldValue else { return }
            if sootEmission > 0 {
                sootTailUntil = CACurrentMediaTime() + 2.2
                if oldValue <= 0 { resume() }
            } else if oldValue > 0 {
                sootTailUntil = CACurrentMediaTime() + 2.2
            }
        }
    }
    var amount: SmokeAmount = .standard
    var cigaretteEmissionMultiplier: Float = 1
    var cigaretteDiameterMultiplier: Float = 1
    var dissipation: SmokeDissipation = .normal {
        didSet {
            if !burning && oldValue != dissipation {
                stoppedAt = CACurrentMediaTime()
                if window?.isVisible == true { resume() }
            }
        }
    }
    var sourceInWindow = NSPoint(x: 300, y: 100)
    var burning = false {
        didSet {
            guard burning != oldValue else { return }
            if burning {
                if let stoppedAt { rebaseSmoke(opacity: dissipation.opacity(after: CACurrentMediaTime() - stoppedAt)) }
                stoppedAt = nil; burstUntil = 0; resume()
            }
            else { stoppedAt = CACurrentMediaTime() }
        }
    }
    var energySaving = false { didSet { preferredFramesPerSecond = energySaving ? 30 : 60; allocateFields() } }

    init?(smokeFrame frame: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let url = Bundle.module.url(forResource: "Smoke.metal", withExtension: "txt", subdirectory: "Resources"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let library = try? device.makeLibrary(source: source, options: nil),
              let kernel = library.makeFunction(name: "advect"),
              let rebase = library.makeFunction(name: "rebaseSmoke"),
              let compute = try? device.makeComputePipelineState(function: kernel),
              let rebasePipeline = try? device.makeComputePipelineState(function: rebase) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let render = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.queue = queue; self.compute = compute; self.rebasePipeline = rebasePipeline; self.render = render
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
        wantsLayer = true
        layer?.isOpaque = false
        framebufferOnly = true
        preferredFramesPerSecond = 60
        enableSetNeedsDisplay = false
        isPaused = true
        delegate = self
        allocateFields()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func allocateFields() {
        guard let device else { return }
        let width = energySaving ? 320 : 640
        let aspect = max(bounds.height / max(bounds.width, 1), 0.3)
        let height = max(96, Int(CGFloat(width) * aspect))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        fields = (0..<2).compactMap { _ in device.makeTexture(descriptor: desc) }
        sootFields = (0..<2).compactMap { _ in device.makeTexture(descriptor: desc) }
        guard fields.count == 2, sootFields.count == 2 else { return }
        let zero = [UInt16](repeating: 0, count: width * height * 4)
        zero.withUnsafeBytes { bytes in
            for field in fields + sootFields { field.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width * 8) }
        }
        current = 0; sootCurrent = 0
    }
    private func rebaseSmoke(opacity: Double) {
        guard opacity < 0.9999, fields.count == 2, sootFields.count == 2,
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { return }
        var fade = Float(max(0, opacity))
        encoder.setComputePipelineState(rebasePipeline)
        encoder.setTexture(fields[current], index: 0); encoder.setTexture(fields[1-current], index: 1)
        encoder.setTexture(sootFields[sootCurrent], index: 2); encoder.setTexture(sootFields[1-sootCurrent], index: 3)
        encoder.setBytes(&fade, length: MemoryLayout<Float>.size, index: 0)
        encoder.dispatchThreads(MTLSize(width: fields[0].width, height: fields[0].height, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding(); current = 1-current; sootCurrent = 1-sootCurrent; command.commit()
    }
    func clear() {
        allocateFields(); hasSmoke = false; lastMouse = nil; lastSource = nil; lastSootSource = nil; sootTailUntil = 0
        if !emits && !burning && sootEmission <= 0 && CACurrentMediaTime() >= sootTailUntil { isPaused = true }
        setNeedsDisplay(bounds)
    }
    func puff(at screenPoint: NSPoint, consumedBurnSeconds: Double) {
        burstScreenPoint = screenPoint
        burstStarted = CACurrentMediaTime()
        burstProfile = PuffProfile(consumedBurnSeconds: consumedBurnSeconds)
        burstUntil = burstStarted + burstProfile.duration
        resume()
    }
    func resume() {
        let now = CACurrentMediaTime()
        if let hiddenAt {
            let hiddenDuration = max(0, now - hiddenAt)
            if let stoppedAt { self.stoppedAt = stoppedAt + hiddenDuration }
            burstUntil += hiddenDuration
            sootTailUntil += hiddenDuration
            self.hiddenAt = nil
        }
        guard (emits && burning) || hasSmoke || now < burstUntil || sootEmission > 0 || now < sootTailUntil else { return }
        lastTime = 0; lastMouse = nil; lastSource = nil; lastSootSource = nil; isPaused = false
    }
    func pausePreservingSmoke() {
        hiddenAt = CACurrentMediaTime()
        isPaused = true; lastTime = 0; lastMouse = nil; lastSource = nil; lastSootSource = nil
    }
    func pauseAndClear() { hasSmoke = false; inhaling = false; sootEmission = 0; sootTailUntil = 0; isPaused = true; lastTime = 0; lastMouse = nil; lastSource = nil; lastSootSource = nil; allocateFields(); needsDisplay = true }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let opacity = burning ? 1.0 : dissipation.opacity(after: now - (stoppedAt ?? now))
        let sootActive = sootEmission > 0 || now < sootTailUntil
        let regularSmokeActive = burning && emits
        let regularSmokeRemainder = hasSmoke && opacity > 0
        if !regularSmokeActive && !regularSmokeRemainder && now > burstUntil && !sootActive {
            if let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
               let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) {
                encoder.endEncoding(); command.present(drawable); command.commit()
            }
            allocateFields(); hasSmoke = false; lastSootSource = nil; sootTailUntil = 0; isPaused = true
            return
        }
        guard fields.count == 2, sootFields.count == 2, let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(), let window else { return }
        let dt = lastTime == 0 ? 1.0 / 60.0 : min(max(now - lastTime, 0), 1.0 / 30.0)
        lastTime = now
        if burning && emits { hasSmoke = true }
        let global = NSEvent.mouseLocation
        let local = window.convertPoint(fromScreen: global)
        let old = lastMouse ?? local
        let sample = MotionSample(dx: local.x - old.x, dy: local.y - old.y, dt: dt)
        lastMouse = local
        let oldSource = lastSource ?? sourceInWindow
        let sourceMotion = MotionSample(dx: sourceInWindow.x - oldSource.x, dy: sourceInWindow.y - oldSource.y, dt: dt, maximumSpeed: 900)
        lastSource = sourceInWindow
        let oldSoot = lastSootSource ?? sootSourceInWindow
        lastSootSource = sootSourceInWindow
        let width = max(bounds.width, 1), height = max(bounds.height, 1)
        func uv(_ point: NSPoint) -> SIMD2<Float> { SIMD2(Float(point.x / width), Float(1 - point.y / height)) }
        let burstElapsed = now - burstStarted
        let puffStrength = now < burstUntil ? burstProfile.envelope(at: burstElapsed) : 0
        let puffProgress = min(1, max(0, burstElapsed / burstProfile.duration))
        let travel = 1 - pow(1 - puffProgress, 2)
        let puffPoint = NSPoint(x: burstScreenPoint.x - 62 * travel, y: burstScreenPoint.y + 18 * travel)
        // Higher smoke settings expand the footprint as well as the emission,
        // keeping the cloud from becoming a uniformly opaque spot.
        let puffAmountScale = sqrt(amount.multiplier * cigaretteEmissionMultiplier)
        var params = SmokeParameters(dt: Float(dt), source: uv(sourceInWindow), mouse: uv(local), previousMouse: uv(old), wind: SIMD2(Float(sample.velocityX / width), Float(-sample.velocityY / height)), emission: (burning && emits ? (inhaling ? 1.0 : 5.0) : 0) * amount.multiplier * cigaretteEmissionMultiplier, time: Float(now - startTime), aspect: Float(width / height), sourceRadius: Float(18 / height) * cigaretteDiameterMultiplier, opacity: Float(opacity), accumulation: dissipation == .noAccumulation ? 0 : 1, puffSource: uv(window.convertPoint(fromScreen: puffPoint)), puffEmission: Float(puffStrength) * puffAmountScale, inhale: inhaling ? 1 : 0, puffSize: Float(burstProfile.size) * puffAmountScale, previousSource: uv(oldSource), sourceWind: SIMD2(Float(sourceMotion.velocityX / width), Float(-sourceMotion.velocityY / height)), cloudVariation: cloudVariation ? 1 : 0, colorTint: colorTint, sootSource: uv(sootSourceInWindow), previousSootSource: uv(oldSoot), sootEmission: sootEmission, sootRadius: Float(9 / height))
        guard let encoder = command.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(compute); encoder.setTexture(fields[current], index: 0); encoder.setTexture(fields[1-current], index: 1)
        encoder.setTexture(sootFields[sootCurrent], index: 2); encoder.setTexture(sootFields[1-sootCurrent], index: 3)
        encoder.setBytes(&params, length: MemoryLayout<SmokeParameters>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: fields[0].width, height: fields[0].height, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)); encoder.endEncoding()
        current = 1-current; sootCurrent = 1-sootCurrent
        guard let output = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        output.setRenderPipelineState(render); output.setFragmentTexture(fields[current], index: 0); output.setFragmentTexture(sootFields[sootCurrent], index: 1); output.setFragmentBytes(&params, length: MemoryLayout<SmokeParameters>.stride, index: 0); output.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4); output.endEncoding()
        command.present(drawable); command.commit()
    }
}
