//
//  MTLRenderer.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/02/18.
//

import Foundation
import MetalKit
import Logging
func getCubeVertexData(cropX: Int, cropY: Int, cropWidth: Int, cropHeight: Int,
                               frameWidth: Int, frameHeight: Int, rotation: VideoRotation) -> [Float] {
    let cropLeft = Float(cropX) / Float(frameWidth)
    let cropRight = Float(cropX + cropWidth) / Float(frameWidth)
    let cropTop = Float(cropY) / Float(frameHeight)
    let cropBottom = Float(cropY + cropHeight) / Float(frameHeight)
    var values:[Float]
    
    //상위 2개 : vertex 좌표, 하위 2개: texture 좌표 -> 텍스쳐 좌표를 제어해 frame drawing
    switch rotation {
    case .rotation_0:
        values = [
            -1.0, -1.0, cropLeft, cropBottom,
            1.0, -1.0, cropRight, cropBottom,
            -1.0, 1.0, cropLeft, cropTop,
            1.0, 1.0, cropRight, cropTop
        ]
    case .rotation_90:
        values = [
            -1.0, -1.0, cropRight, cropBottom,
            1.0, -1.0, cropRight, cropTop,
            -1.0, 1.0, cropLeft, cropBottom,
            1.0, 1.0, cropLeft, cropTop
        ]
    case .rotation_180:
        values = [
            -1.0, -1.0, cropRight, cropTop,
            1.0, -1.0, cropLeft, cropTop,
            -1.0, 1.0, cropRight, cropBottom,
            1.0, 1.0, cropLeft, cropBottom
        ]
    case .rotation_270:
        values = [
            -1.0, -1.0, cropLeft, cropTop,
            1.0, -1.0, cropLeft, cropBottom,
            -1.0, 1.0, cropRight, cropTop,
            1.0, 1.0, cropRight, cropBottom
        ]
    }
    return values
}


open class MTLRenderer {
    var view : MTKView!
    var device: MTLDevice? = nil
    var commandQueue: MTLCommandQueue? = nil
    var defaultLibrary: MTLLibrary? = nil
    var pipelineState: MTLRenderPipelineState? = nil
    var vertexBuffer: MTLBuffer? = nil
    
    var oldFrameWidth: Int = 0
    var oldFrameHeight: Int = 0
    var oldCropWidth: Int = 0
    var oldCropHeight: Int = 0
    var oldCropX: Int = 0
    var oldCropY: Int = 0
    var oldRotation: VideoRotation = .rotation_0
    let semaphore = DispatchSemaphore(value: 1)
    let logger = Logger(label: "MTLRenderer")
    var currentMetalDevice: MTLDevice? { return device }
    
    func addRenderingDestination(view: MTKView) -> Bool {
        return setupWithView(view: view)
    }
    
    func uploadTexturesToRenderEncoder(renderEncoder: MTLRenderCommandEncoder) {
        
    }
    
    open func shaderString() -> String? {
        return nil
    }
    public func setupWithView(view: MTKView) -> Bool {
        if !setupMetal() {
            return false
        }
        //MTKView 설정
        self.view = view
        view.device = self.device
        view.preferredFramesPerSecond = 30
        view.autoResizeDrawable = false
        loadAssets()
        
        let vertexBufferArray:[Float] = [Float].init(repeating: 0, count: 16)
        let dataSize = vertexBufferArray.count * MemoryLayout.size(ofValue: vertexBufferArray[0])
        self.vertexBuffer = device?.makeBuffer(bytes: vertexBufferArray, length: dataSize, options: [])
        return true
    }
    
    //MARK - MetalKit 초기화
    private func setupMetal() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return false
        }
        self.device = device
        //MTLCommandQueue 생성
        self.commandQueue = device.makeCommandQueue()
        //shader 설정
        guard let shader = shaderString() else {
            return false
        }
        
        //MTLLibrary 설정
        do {
            self.defaultLibrary = try device.makeLibrary(source: shader, options: nil)
        } catch  {
            logger.error("make metal library fail: \(error)")
            return false
        }
        return true
    }
    
    private func loadAssets() {
        guard let device = self.device,
              let library = self.defaultLibrary else { return }
        //shader vertexFunction
        let vertexFunction = library.makeFunction(name: "vertexPassthrough")
        //shader fragmentFunction
        let fragmentFunction = library.makeFunction(name: "fragmentColorConversion")
        //파이프라인 디스크립터 설정
        let pipeLineDescriptor = MTLRenderPipelineDescriptor()
        pipeLineDescriptor.label = "pipeline"
        pipeLineDescriptor.vertexFunction = vertexFunction
        pipeLineDescriptor.fragmentFunction = fragmentFunction
        pipeLineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeLineDescriptor.depthAttachmentPixelFormat = .invalid
        
        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipeLineDescriptor)
        } catch  {
            logger.error("fail to makeRenderPipelineState: \(error)")
        }
    }
    
    
    func render() {
        //command 버퍼 생성
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        commandBuffer.label = "metalcommandBuffer"
        //command 종료시 wakeup
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let `self` = self else { return }
            self.semaphore.signal()
        }
        
        // 새로운 렌더 패스 디스크립터 설정
        if let renderPassDescriptor = view.currentRenderPassDescriptor {
            //렌더 인코더 생성
            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.label = "renderEncoderLabel"
                renderEncoder.pushDebugGroup("Frame Draw")
                renderEncoder.setRenderPipelineState(self.pipelineState!)
                //버텍스 버퍼 설정
                renderEncoder.setVertexBuffer(self.vertexBuffer!, offset: 0, index: 0)
                //텍스쳐 버퍼 설정
                uploadTexturesToRenderEncoder(renderEncoder: renderEncoder)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
                renderEncoder.popDebugGroup()
                renderEncoder.endEncoding()
                //drawable 등록
                commandBuffer.present(view.currentDrawable!)
            }
        }
        //commandBuffer 커밋
        commandBuffer.commit()
    }
    
    //MARK: 비디오 프레임의 width, height crop, 회전 위치에 따라 vertex 좌표 설정 
    open func setupTexturesForFrame(frame: VideoFrame) -> Bool {
        let rotation = frame.rotation
        let frameWidth = CVPixelBufferGetWidth(frame.pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(frame.pixelBuffer)
        let cropWidth = frame.cropWidth
        let cropHeight = frame.cropHeight
        let cropX = frame.cropX
        let cropY = frame.cropY
        if cropX != oldCropX || cropY != oldCropY || cropWidth != oldCropWidth ||
            cropHeight != oldCropHeight || cropWidth != oldCropWidth || rotation != oldRotation ||
            frameWidth != oldFrameWidth || frameHeight != oldFrameHeight {
            //프레임을 표시할 버텍스 좌표 (회전 방향에 따라 변경)
            let vertexArray = getCubeVertexData(cropX: cropX, cropY: cropY, cropWidth: cropWidth, cropHeight: cropHeight, frameWidth: frameWidth, frameHeight: frameHeight, rotation: rotation)
            //print("vertex:\(vertexArray)")
            //버텍스 좌표 복사
            let vertex = vertexArray.withUnsafeBytes { return $0 }
            vertexBuffer?.contents().copyMemory(from: vertex.baseAddress!, byteCount: vertex.count)

            oldCropX = cropX
            oldCropY = cropY
            oldCropWidth = cropWidth
            oldCropHeight = cropHeight
            oldRotation = rotation
            oldFrameWidth = frameWidth
            oldFrameHeight = frameHeight
        }
        return true
    }
    
    public func draw(frame: VideoFrame) {
        semaphore.wait()
        if setupTexturesForFrame(frame: frame) {
            render()
        } else {
            print("fail to draw")
            semaphore.signal()
        }
    }
    
    public func drawBlankAndWait() {
        semaphore.wait()
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let `self` = self else { return }
            self.semaphore.signal()
        }
        if !setupBlank() {
            semaphore.signal()
        }
    }
    
    private func setupBlank() -> Bool {
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return false }
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let `self` = self else { return }
            self.semaphore.signal()
        }
        
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return false }
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            renderEncoder.endEncoding()
            commandBuffer.present(view.currentDrawable!)
            commandBuffer.commit()
            //commandBuffer.waitUntilScheduled()
        }
        return true
    }
    
}
