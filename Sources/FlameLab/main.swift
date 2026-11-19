import AppKit
import MetalKit

private struct Parameters {
    var dt: Float = 1 / 60
    var time: Float = 0
    var fuel: Float = 0.5
    var mode: Float = 0
    var mouse = SIMD2<Float>(-10, -10)
    var mousePrev = SIMD2<Float>(-10, -10)
    var wind = SIMD2<Float>(0, 0)
    var nozzle = SIMD2<Float>(0.5, 0.88)
    var sourceAir = SIMD2<Float>(0, 0)
}

final class FlameLabView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let advancePipeline: MTLComputePipelineState
    private let divergencePipeline: MTLComputePipelineState
    private let pressurePipeline: MTLComputePipelineState
    private let projectPipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let footage: MTLTexture
    private let gridWidth = 96, gridHeight = 192
    private var velocity: [MTLTexture] = [], scalars: [MTLTexture] = [], pressures: [MTLTexture] = []
    private var divergenceField: MTLTexture!
    private var velocityIndex = 0, scalarIndex = 0, pressureIndex = 0
    private var params = Parameters()
    private var lastTime: CFTimeInterval = 0, start = CACurrentMediaTime()
    private var oldMouse: NSPoint?, oldNozzle: SIMD2<Float>?
    private var draggingNozzle = false
    private var lastReport: CFTimeInterval = 0
    var onMetrics: ((String) -> Void)?
    var power: Float = 0.5 { didSet { params.fuel = power } }
    var debugMode: Float = 4 { didSet { params.mode = debugMode } }

    init(labFrame frame: NSRect) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw LabError("无法创建 Metal 设备或命令队列") }
        guard let url = Bundle.module.url(forResource: "FlameLab.metal", withExtension: "txt", subdirectory: "Resources") else { throw LabError("找不到火焰着色器资源") }
        let source = try String(contentsOf: url, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        func compute(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw LabError("找不到计算函数 \(name)") }
            return try device.makeComputePipelineState(function: fn)
        }
        self.queue = queue
        advancePipeline = try compute("advance")
        divergencePipeline = try compute("divergence")
        pressurePipeline = try compute("pressure")
        projectPipeline = try compute("project")
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard let footageURL = Bundle.module.url(forResource: "LighterFootage", withExtension: "png", subdirectory: "Resources") else { throw LabError("找不到实拍火焰素材") }
        footage = try MTKTextureLoader(device: device).newTexture(URL: footageURL, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
        super.init(frame: frame, device: device)
        wantsLayer = true; layer?.isOpaque = false
        colorPixelFormat = .bgra8Unorm; clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true; preferredFramesPerSecond = 60; delegate = self
        try allocate()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func allocate() throws {
        guard let device else { throw LabError("Metal 设备不可用") }
        func texture() throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: gridWidth, height: gridHeight, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .shared
            guard let t = device.makeTexture(descriptor: d) else { throw LabError("无法分配模拟网格") }
            let zero = [UInt16](repeating: 0, count: gridWidth * gridHeight * 4)
            zero.withUnsafeBytes { t.replace(region: MTLRegionMake2D(0, 0, gridWidth, gridHeight), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: gridWidth * 8) }
            return t
        }
        velocity = try (0..<2).map { _ in try texture() }
        scalars = try (0..<2).map { _ in try texture() }
        pressures = try (0..<2).map { _ in try texture() }
        divergenceField = try texture()
    }
    func reset() {
        do { try allocate(); velocityIndex = 0; scalarIndex = 0; pressureIndex = 0; oldMouse = nil; lastTime = 0 }
        catch { onMetrics?("重置失败：\(error.localizedDescription)") }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override var acceptsFirstResponder: Bool { true }
    private func uv(_ point: NSPoint) -> SIMD2<Float> {
        SIMD2(Float(point.x / max(1,bounds.width)), Float(1 - point.y / max(1,bounds.height)))
    }
    override func mouseDown(with event: NSEvent) {
        let p = uv(convert(event.locationInWindow, from: nil))
        draggingNozzle = simd_length(p - params.nozzle) < 0.12
    }
    override func mouseDragged(with event: NSEvent) {
        guard draggingNozzle else { return }
        let p = uv(convert(event.locationInWindow, from: nil))
        params.nozzle = SIMD2(min(0.85,max(0.15,p.x)), min(0.93,max(0.45,p.y)))
    }
    override func mouseUp(with event: NSEvent) { draggingNozzle = false }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let window, let command = queue.makeCommandBuffer(), let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor else { return }
        let now = CACurrentMediaTime()
        let elapsed = lastTime == 0 ? 1.0 / 60 : max(1.0 / 1000, now - lastTime)
        let dt = min(1.0 / 30, max(1.0 / 240, elapsed))
        lastTime = now; params.dt = Float(dt); params.time = Float(now - start)
        let mouse = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let previous = oldMouse ?? mouse; oldMouse = mouse
        let mouseUV = uv(mouse), prevUV = uv(previous)
        params.mode = debugMode
        params.mouse = mouseUV; params.mousePrev = prevUV
        params.wind = draggingNozzle ? .zero : simd_clamp((mouseUV - prevUV) / Float(dt), SIMD2(repeating: -1.2), SIMD2(repeating: 1.2))
        let old = oldNozzle ?? params.nozzle
        params.sourceAir = simd_clamp((old - params.nozzle) / Float(dt), SIMD2(repeating: -1), SIMD2(repeating: 1))
        oldNozzle = params.nozzle
        let grid = MTLSize(width: gridWidth, height: gridHeight, depth: 1)
        let group = MTLSize(width: 8, height: 8, depth: 1)
        func passCompute(_ pipeline: MTLComputePipelineState, _ textures: [MTLTexture], params useParams: Bool = false) -> Bool {
            guard let encoder = command.makeComputeCommandEncoder() else { return false }
            encoder.setComputePipelineState(pipeline)
            for (i, texture) in textures.enumerated() { encoder.setTexture(texture, index: i) }
            if useParams { encoder.setBytes(&params, length: MemoryLayout<Parameters>.stride, index: 0) }
            encoder.dispatchThreads(grid, threadsPerThreadgroup: group); encoder.endEncoding(); return true
        }
        let vNext = 1-velocityIndex, sNext = 1-scalarIndex
        guard passCompute(advancePipeline, [velocity[velocityIndex], scalars[scalarIndex], velocity[vNext], scalars[sNext]], params: true),
              passCompute(divergencePipeline, [velocity[vNext], divergenceField]) else { return }
        for _ in 0..<24 {
            guard passCompute(pressurePipeline, [pressures[pressureIndex], divergenceField, pressures[1-pressureIndex]]) else { return }
            pressureIndex = 1-pressureIndex
        }
        guard passCompute(projectPipeline, [velocity[vNext], pressures[pressureIndex], velocity[velocityIndex]]) else { return }
        scalarIndex = sNext
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPipeline); encoder.setFragmentTexture(scalars[scalarIndex], index: 0)
        encoder.setFragmentTexture(velocity[velocityIndex], index: 1)
        encoder.setFragmentTexture(footage, index: 2)
        encoder.setFragmentBytes(&params, length: MemoryLayout<Parameters>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
        command.present(drawable)
        if now - lastReport > 0.5 {
            lastReport = now
            let fps = 1 / elapsed
            command.addCompletedHandler { [weak self] buffer in
                let gpu = max(0, buffer.gpuEndTime - buffer.gpuStartTime) * 1000
                let status = buffer.status == .error ? "GPU 错误：\(buffer.error?.localizedDescription ?? "未知")" : String(format: "%.0f FPS   GPU %.2f ms   网格 96 × 192   压力迭代 24 次", fps, gpu)
                DispatchQueue.main.async { self?.onMetrics?(status) }
            }
        }
        command.commit()
    }
}

struct LabError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }

final class LabController: NSWindowController {
    private var renderer: FlameLabView?
    private let stats = NSTextField(labelWithString: "正在启动 Metal…")
    private let backdrop = NSView()
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Flame Lab · Metal 火焰原型"; window.center(); window.minSize = NSSize(width: 560, height: 650)
        super.init(window: window)
        let content = NSView(); window.contentView = content
        backdrop.wantsLayer = true; backdrop.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1).cgColor
        backdrop.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(backdrop)
        let header = NSTextField(labelWithString: "独立火焰调试场景")
        header.font = .boldSystemFont(ofSize: 19)
        let power = NSSegmentedControl(labels: ["小火", "中火", "大火"], trackingMode: .selectOne, target: self, action: #selector(powerChanged(_:)))
        power.selectedSegment = 1
        let modes = NSSegmentedControl(labels: ["实拍静态", "实拍动态", "流体", "温度", "速度", "轻量"], trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
        modes.selectedSegment = 0
        let reset = NSButton(title: "重置模拟", target: self, action: #selector(resetSimulation))
        let help = NSTextField(wrappingLabelWithString: "在画面中快速移动鼠标可扇风；按住火焰底部拖动喷嘴可测试相对气流。深灰背景用于观察透明火焰。")
        help.font = .systemFont(ofSize: 12); help.textColor = .secondaryLabelColor
        stats.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let controls = NSStackView(views: [header, power, modes, reset, help, stats])
        controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 9
        controls.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), controls.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), controls.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            backdrop.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 14), backdrop.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20), backdrop.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20), backdrop.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        do {
            let view = try FlameLabView(labFrame: .zero); renderer = view
            view.onMetrics = { [weak self] in self?.stats.stringValue = $0 }
            view.translatesAutoresizingMaskIntoConstraints = false; backdrop.addSubview(view)
            NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: backdrop.topAnchor), view.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor), view.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor), view.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor)])
        } catch { stats.stringValue = "Metal 初始化失败：\(error.localizedDescription)" }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func powerChanged(_ sender: NSSegmentedControl) { renderer?.power = [0.0, 0.5, 1.0][sender.selectedSegment] }
    @objc private func modeChanged(_ sender: NSSegmentedControl) { renderer?.debugMode = Float([4, 5, 0, 1, 2, 3][sender.selectedSegment]) }
    @objc private func resetSimulation() { renderer?.reset() }
}

final class LabApp: NSObject, NSApplicationDelegate {
    private var controller: LabController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controller = LabController(); controller?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = LabApp(); app.delegate = delegate
app.run()
