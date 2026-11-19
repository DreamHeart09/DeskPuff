import Foundation
import Metal
import MetalKit
import ImageIO
import simd

private struct Params {
    var dt: Float = 1/60, time: Float = 0, fuel: Float = 0.5, mode: Float = 0
    var mouse = SIMD2<Float>(-10,-10), mousePrev = SIMD2<Float>(-10,-10), wind = SIMD2<Float>(0,0)
    var nozzle = SIMD2<Float>(0.5,0.88), sourceAir = SIMD2<Float>(0,0)
}

@main struct SmokeCheck {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw Failure("Metal device unavailable") }
        let source = try String(contentsOfFile: "Sources/FlameLab/Resources/FlameLab.metal.txt", encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else { throw Failure("missing \(name)") }
            return try device.makeComputePipelineState(function: function)
        }
        let advance = try pipeline("advance"), divergence = try pipeline("divergence"), pressure = try pipeline("pressure"), project = try pipeline("project")
        let width = 96, height = 192
        func texture() throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]; descriptor.storageMode = .shared
            guard let result = device.makeTexture(descriptor: descriptor) else { throw Failure("texture allocation") }
            let zero = [UInt16](repeating: 0, count: width*height*4)
            zero.withUnsafeBytes { result.replace(region: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width*8) }
            return result
        }
        let v = try (0..<2).map { _ in try texture() }, s = try (0..<2).map { _ in try texture() }, p = try (0..<2).map { _ in try texture() }
        let divBefore = try texture(), divAfter = try texture()
        let grid = MTLSize(width: width,height: height,depth: 1), group = MTLSize(width: 8,height: 8,depth: 1)
        var sIndex = 0, pIndex = 0, params = Params(), gpuTotal = 0.0
        if CommandLine.arguments.count > 2, let power = Float(CommandLine.arguments[2]) { params.fuel = min(1,max(0,power)) }
        if CommandLine.arguments.count > 5, let wind = Float(CommandLine.arguments[5]) {
            params.mousePrev = SIMD2<Float>(0.38, 0.75); params.mouse = SIMD2<Float>(0.62, 0.75)
            params.wind = SIMD2<Float>(min(1,max(-1,wind)), 0)
        }
        let frames = CommandLine.arguments.count > 3 ? min(3600, max(1, Int(CommandLine.arguments[3]) ?? 120)) : 120
        for frame in 0..<frames {
            params.time = Float(frame)/60
            guard let command = queue.makeCommandBuffer() else { throw Failure("command buffer") }
            func dispatch(_ pipeline: MTLComputePipelineState, _ textures: [MTLTexture], withParams: Bool = false) throws {
                guard let encoder = command.makeComputeCommandEncoder() else { throw Failure("compute encoder") }
                encoder.setComputePipelineState(pipeline)
                for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
                if withParams { encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0) }
                encoder.dispatchThreads(grid, threadsPerThreadgroup: group); encoder.endEncoding()
            }
            try dispatch(advance, [v[0],s[sIndex],v[1],s[1-sIndex]], withParams: true)
            try dispatch(divergence, [v[1], divBefore])
            for _ in 0..<24 { try dispatch(pressure, [p[pIndex],divBefore,p[1-pIndex]]); pIndex = 1-pIndex }
            try dispatch(project, [v[1],p[pIndex],v[0]])
            try dispatch(divergence, [v[0],divAfter])
            command.commit(); command.waitUntilCompleted()
            guard command.status == .completed else { throw Failure("GPU execution: \(command.error?.localizedDescription ?? "unknown")") }
            gpuTotal += max(0,command.gpuEndTime-command.gpuStartTime); sIndex = 1-sIndex
        }
        func read(_ texture: MTLTexture) -> [UInt16] {
            var data = [UInt16](repeating: 0,count: width*height*4)
            data.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width*8, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0) }
            return data
        }
        let state = read(s[sIndex]), before = read(divBefore), after = read(divAfter)
        func f(_ v: UInt16) -> Float { Float(Float16(bitPattern: v)) }
        var temp: Float = 0, fuel: Float = 0, reaction: Float = 0, a = 0.0, b = 0.0
        for i in 0..<(width*height) {
            let temperature = f(state[i*4]), gas = f(state[i*4+1]), burn = f(state[i*4+2])
            guard temperature.isFinite, gas.isFinite, burn.isFinite else { throw Failure("nonfinite state") }
            temp = max(temp, temperature); fuel = max(fuel, gas); reaction = max(reaction,burn)
            let pre = Double(f(before[i*4])), post = Double(f(after[i*4]))
            guard pre.isFinite, post.isFinite else { throw Failure("nonfinite divergence") }
            a += pre*pre; b += post*post
        }
        guard temp > 0.01, fuel > 0.01, reaction > 0.01 else { throw Failure("no sustained reaction") }
        guard b < a else { throw Failure("pressure projection increased divergence: \(a) -> \(b)") }
        if CommandLine.arguments.count > 1 {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertexMain"); descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
            descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
            let render = try device.makeRenderPipelineState(descriptor: descriptor)
            let outputDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 384, height: 768, mipmapped: false)
            outputDesc.storageMode = .shared; outputDesc.usage = [.renderTarget, .shaderRead]
            guard let output = device.makeTexture(descriptor: outputDesc), let command = queue.makeCommandBuffer() else { throw Failure("render target") }
            let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0); pass.colorAttachments[0].storeAction = .store
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Failure("render encoder") }
            let footage = try MTKTextureLoader(device: device).newTexture(URL: URL(fileURLWithPath: "Sources/FlameLab/Resources/LighterFootage.png"), options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
            encoder.setRenderPipelineState(render); encoder.setFragmentTexture(s[sIndex], index: 0); encoder.setFragmentTexture(v[0], index: 1); encoder.setFragmentTexture(footage, index: 2)
            if CommandLine.arguments.count > 4, let mode = Float(CommandLine.arguments[4]) { params.mode = mode }
            encoder.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
            command.commit(); command.waitUntilCompleted()
            guard command.status == .completed else { throw Failure("render failed") }
            var pixels = [UInt8](repeating: 0, count: 384*768*4)
            pixels.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 384*4, from: MTLRegionMake2D(0,0,384,768), mipmapLevel: 0) }
            guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                  let image = CGImage(width: 384, height: 768, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 384*4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
                  let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil) else { throw Failure("PNG output") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure("PNG write") }
        }
        print(String(format: "Metal %@: max temperature %.3f, fuel %.3f, reaction %.3f; divergence RMS ratio %.3f; GPU compute %.2f ms/frame",device.name,temp,fuel,reaction,sqrt(b/a),gpuTotal/Double(frames)*1000))
    }
}
private struct Failure: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
