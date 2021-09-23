//
//  MTLNV12Renderer.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/02/19.
//

import Foundation
import MetalKit
public class MTLNV12Renderer : MTLRenderer {
    let shaderSource: String =
    """
    using namespace metal;

    typedef struct {
        packed_float2 position;
        packed_float2 texcoord;
    } Vertex;

    typedef struct{
        float4 position[[position]];
        float2 texcoord;
    } Varyings;

    vertex Varyings vertexPassthrough(constant Vertex *vertices[[buffer(0)]],
                                      unsigned int vid[[vertex_id]]) {
        Varyings out;
        constant Vertex &v = vertices[vid];
        out.position = float4(float2(v.position), 0.0, 1.0);
        out.texcoord = v.texcoord;
        return out;
    }

    fragment half4 fragmentColorConversion(
        Varyings in[[stage_in]],
        texture2d<float, access::sample> textureY[[texture(0)]],
        texture2d<float, access::sample> textureCbCr[[texture(1)]]) {
      constexpr sampler s(address::clamp_to_edge, filter::linear);
      float y;
      float2 uv;
      y = textureY.sample(s, in.texcoord).r;
      uv = textureCbCr.sample(s, in.texcoord).rg - float2(0.5, 0.5);
      float4 out = float4(y + 1.403 * uv.y, y - 0.344 * uv.x - 0.714 * uv.y, y + 1.770 * uv.x, 1.0);
      return half4(out);
    }
    """
    
    var textureCache: CVMetalTextureCache? = nil
    var yTexture: MTLTexture? = nil
    var crCbTexture: MTLTexture? = nil
    
    public override init() {
        super.init()
    }
    
    public override func shaderString() -> String? {
        return shaderSource
    }
    
    func initializeTextureCache() -> Bool {
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, currentMetalDevice!, nil, &textureCache)
        if status != kCVReturnSuccess {
            return false
        }
        return true
    }
    
    public override func addRenderingDestination(view: MTKView) -> Bool {
        if super.addRenderingDestination(view: view) {
            return self.initializeTextureCache()
        }
        return false
    }
    
    // MARK : MetalView에 그리기 위한 버텍스 및 텍스쳐 버퍼 설정
    public override func setupTexturesForFrame(frame: VideoFrame) -> Bool {
        if !super.setupTexturesForFrame(frame: frame) {
            return false
        }
        
        // y texture
        var lumaTexture: MTLTexture? = nil
        var chromaTexture: MTLTexture? = nil
        var outTexture: CVMetalTexture? = nil
        // LumaTexture (Y)
        let lumaWidth = CVPixelBufferGetWidthOfPlane(frame.pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(frame.pixelBuffer, 0)
        var indexPlane = 0
        var result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, frame.pixelBuffer, nil, .r8Unorm, lumaWidth, lumaHeight, indexPlane, &outTexture)
        if result == kCVReturnSuccess {
            lumaTexture = CVMetalTextureGetTexture(outTexture!)
        }
        
        outTexture = nil
        // Chroma (CrCb) texture
        indexPlane = 1
        result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, frame.pixelBuffer, nil, .rg8Unorm, lumaWidth / 2, lumaHeight / 2, indexPlane, &outTexture)
        if result == kCVReturnSuccess {
            chromaTexture = CVMetalTextureGetTexture(outTexture!)
        }
        outTexture = nil
        
        if lumaTexture != nil && chromaTexture != nil {
            yTexture = lumaTexture
            crCbTexture = chromaTexture
            return true
        }
        return false
    }
    
    override func uploadTexturesToRenderEncoder(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setFragmentTexture(yTexture, index: 0)
        renderEncoder.setFragmentTexture(crCbTexture, index: 1)
    }
    
}


