//
//  nalu_rewriter.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/07.
//

import Foundation
import AVFoundation
import VideoToolbox

let kAnnexBHeaderBytes: [UInt8] = [0, 0, 0, 1]

/*
 * AnnexB Format:
 * ([start code] NALU) | ([start code] NALU) |
 *
 * AVCC Format:
 * ([extradata]) | ([length] NALU) | ([length] NULU) |
 */



/*
 * VideoToolbox에서 인코드된 Raw 인코드 데이터를 RTP 전송을 위해 AnnexB 형태로 변경 -> H.265 도 동일 할 것으로 예상
 */


func H264SampleBufferToAnnexBBuffer(sampleBuffer: CMSampleBuffer, isKeyFrame: Bool) -> Data? {
    guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        return nil
    }
    var status:OSStatus = noErr
    var nalu_header_size: Int32 = 4
    var annexBuffer  = Data()
    // 키프레임의 경우 파라미터 셋(SPS 와 PPS) 설정
    if isKeyFrame {
        var count: Int = 0
        //H264 ParameterSet 이 개수와, nal unit 의 헤더 사이즈 가져오기 : count, nalu_header_size
        status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                                    parameterSetIndex: 0,
                                                                    parameterSetPointerOut: nil,
                                                                    parameterSetSizeOut: nil,
                                                                    parameterSetCountOut: &count,
                                                                    nalUnitHeaderLengthOut: &nalu_header_size)
        if status != noErr {
            print("Failed to get parameter set")
            return nil
        }
        var param_set_size: Int = 0
        let param_set = UnsafeMutablePointer<UnsafePointer<UInt8>?>.allocate(capacity: 1)
        for i in 0..<count {
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                                        parameterSetIndex: i,
                                                                        parameterSetPointerOut: param_set,
                                                                        parameterSetSizeOut: &param_set_size,
                                                                        parameterSetCountOut: nil,
                                                                        nalUnitHeaderLengthOut: nil)
            guard status == noErr , let ptr = param_set.pointee else { return nil }
            annexBuffer.append(contentsOf: kAnnexBHeaderBytes)
            annexBuffer.append(Data(bytes: ptr, count: param_set_size))
            //let data = Data(bytes: ptr, count: param_set_size)
            //print(data.hexDescription)
        }
        param_set.deallocate()
        //print("sps and pps:\(annexBuffer.hexDescription)")
    }
    

    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
        print("Fail to get sample buffer's block buffer.")
        return nil
    }
    //해당 버퍼가 연속된 주소를 갖도록 설정
    var continuousBuffer: CMBlockBuffer? = nil
    if !CMBlockBufferIsRangeContiguous(blockBuffer, atOffset: 0, length: 0) {
        status = CMBlockBufferCreateContiguous(allocator: nil,
                                               sourceBuffer: blockBuffer,
                                               blockAllocator: nil,
                                               customBlockSource: nil,
                                               offsetToData: 0,
                                               dataLength: 0,
                                               flags: 0,
                                               blockBufferOut: &continuousBuffer)
        if status != noErr {
            print("Failed to flatten non-contiguous block buffer: \(status)")
            return nil
        }
    } else {
        continuousBuffer = blockBuffer
    }
    
    guard let buffer = continuousBuffer else {
        print("Failed to get continuousBuffer")
        return nil
    }
    
    var data_ptr: UnsafeMutablePointer<Int8>? = nil
    let blockBufferSize = CMBlockBufferGetDataLength(buffer)
    //print("block buffer size:\(blockBufferSize)")
    status = CMBlockBufferGetDataPointer(buffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &data_ptr)
    if status != noErr {
        return nil
    }
    
    var remainBytes:Int = blockBufferSize
    guard var ptr = data_ptr else {
        return nil
    }
    
    // |packet_size|packet| -> packet_size : nalu_header_size(4bytes)
    // 해당 프레임이 P 프레임인 경우 -> 6(SEI), 5(IDR), I Prame 인경우 1(non-IDR)
    // 나중에 추가적으로 필요 없는 경우 SEI 정보를 제거 하도록 할 것
    while(remainBytes > 0) {
        //4byte: 패킷 길이
        let packet_size = ptr.withMemoryRebound(to: UInt32.self, capacity: 1){ CFSwapInt32BigToHost($0.pointee)}
        let nalu_header_ptr = ptr + Int(nalu_header_size)
        //print("nalu type: \(nalu_header_ptr.pointee)")
        //skip sei
        if nalu_header_ptr.pointee != 6 {
            annexBuffer.append(contentsOf: kAnnexBHeaderBytes)
            let data = Data(bytes: ptr + Int(nalu_header_size), count: Int(packet_size))
            annexBuffer.append(data)
        }
        let writtenBytes = packet_size + UInt32(kAnnexBHeaderBytes.count)
        remainBytes -= Int(writtenBytes)
        ptr += Int(writtenBytes)
    }
    return annexBuffer
}

/*
 * RTP로 들어온 AnnexB 형태로 인코드된 스트림을 VideoToolBox를 통해 디코딩하기 위해 CMSampleBuffer 형태로 변경
 */
func H264AnnexBBufferToCMSampleBuffer(buffer: Data,
                                     video_format: CMVideoFormatDescription,
                                     presentationTime: Double,
                                     out_sample_buffer: inout CMSampleBuffer?,
                                     memory_pool: CMMemoryPool) -> Bool {
    
    guard let buf = buffer.withUnsafeBytes({ return $0 }).bindMemory(to: UInt8.self).baseAddress
    else { return false }
    
    //NalType 정보
    let reader = AnnexBBufferReader(data: buf, count: buffer.count)
    var data: UnsafePointer<UInt8>? = nil
    var data_len: Int32 = 0
    
    
    //sps 가 있는 경우 sps  pps 는 스킵
    if reader.seekToNaluOfType(type: .kSps) {
        if !reader.readNalUnit(buffer: &data, count: &data_len) {
            print("fail to read sps")
            return false
        }
        if !reader.readNalUnit(buffer: &data, count: &data_len) {
            print("fail to read pps")
            return false
        }
    } else {
        reader.resetStart()
    }
    
    //수신된 데이터를 저장할 블럭 버퍼 생성
    var block_buffer: CMBlockBuffer? = nil
    let block_allocator = CMMemoryPoolGetAllocator(memory_pool)
    var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                    memoryBlock: nil,
                                                    blockLength: reader.remainBytes(),
                                                    blockAllocator: block_allocator,
                                                    customBlockSource: nil,
                                                    offsetToData: 0,
                                                    dataLength: reader.remainBytes(),
                                                    flags: kCMBlockBufferAssureMemoryNowFlag,
                                                    blockBufferOut: &block_buffer)
    
    if status != kCMBlockBufferNoErr {
        print("fail to create block buffer.")
        return false
    }
    
    var contiguous_buffer : CMBlockBuffer? = nil
    if(!CMBlockBufferIsRangeContiguous(block_buffer!, atOffset: 0, length: 0)) {
        status = CMBlockBufferCreateContiguous(allocator: kCFAllocatorDefault,
                                               sourceBuffer: block_buffer!,
                                               blockAllocator: block_allocator,
                                               customBlockSource: nil,
                                               offsetToData: 0,
                                               dataLength: 0,
                                               flags: 0,
                                               blockBufferOut: &contiguous_buffer)
        if status != noErr {
            print("fail to flatten non-contiguous block buffer: \(status)")
            return false
        }
    } else {
        contiguous_buffer = block_buffer
        block_buffer = nil
    }
    
    //블럭 버퍼의 시작 위치와 크기 확인
    var block_buffer_size: Int = 0
    var data_ptr: UnsafeMutablePointer<Int8>? = nil
    status = CMBlockBufferGetDataPointer(contiguous_buffer!,
                                         atOffset: 0,
                                         lengthAtOffsetOut: nil,
                                         totalLengthOut: &block_buffer_size,
                                         dataPointerOut: &data_ptr)
    if status != kCMBlockBufferNoErr {
        print("fail to get block buffer data pointer")
        return false
    }
    
    //저장할 크기와 다른 블럭버퍼가 할당되었다면 에러 처리
    if block_buffer_size != reader.remainBytes() {
        print("allocation buffer size is narrow")
        return false
        
    }
    
    guard let ptr = data_ptr?.withMemoryRebound(to: UInt8.self, capacity: block_buffer_size, {
                                                    return $0 }) else { return false }
    //버퍼의 시작위치와 버퍼의 크기를 이용해 AVCC 버퍼 형식으로 변환할 writer 생성
    let writer = AvccBufferWriter(buffer: ptr, count: block_buffer_size)
    while (reader.remainBytes() > 0) {
        var nalu_data_ptr: UnsafePointer<UInt8>? = nil
        var nalu_data_len: Int32 = 0
        //NalUnit의 정보를 읽고 해당 데이터를 avcc 형식으로 버퍼에 쓰기
        if reader.readNalUnit(buffer: &nalu_data_ptr, count: &nalu_data_len) {
            _ = writer.writeNalu(data: nalu_data_ptr!, count: Int(nalu_data_len))
        }
    }
    
    let timestamp = Int64(presentationTime * kNumNanosecsPerSec)
    var timing = CMSampleTimingInfo(duration: .invalid,
                                    presentationTimeStamp: CMTimeMake(value: timestamp, timescale: Int32(kNumNanosecsPerSec)),
                                    decodeTimeStamp: .invalid)
    //out_sample_buffer 에 CMSampleBuffer 생성
    status = CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                  dataBuffer: contiguous_buffer,
                                  dataReady: true,
                                  makeDataReadyCallback: nil,
                                  refcon: nil,
                                  formatDescription: video_format,
                                  sampleCount: 1,
                                  sampleTimingEntryCount: 1,
                                  sampleTimingArray: &timing,
                                  sampleSizeEntryCount: 0,
                                  sampleSizeArray: nil,
                                  sampleBufferOut: &out_sample_buffer);
    if status != noErr {
        print("fail to create sample buffer: \(status)")
        return false
    }
    return true
}


func readParameterSet(data: UnsafePointer<UInt8>, count: Int,
                      sps: inout UnsafePointer<UInt8>?, spsLength: inout Int32,
                      pps: inout UnsafePointer<UInt8>?, ppsLength: inout Int32) -> Bool {
    let reader = AnnexBBufferReader(data: data, count: count)
    if !reader.seekToNaluOfType(type: .kSps) {
        return false
    }
    if !reader.readNalUnit(buffer: &sps, count: &spsLength) {
        print("read fail to sps")
        return false
    }
    
    if !reader.readNalUnit(buffer: &pps, count: &ppsLength) {
        print("read fail to sps")
        return false
    }
    return true
}


func createVideoForamtDescription(buffer: UnsafePointer<UInt8>, count: Int) -> CMVideoFormatDescription? {
    let reader = AnnexBBufferReader(data: buffer, count: count)
    if !reader.seekToNaluOfType(type: .kSps) {
        return nil
    }
    //read sps + pps
    var sps: UnsafePointer<UInt8>? = nil
    var spsLength: Int32 = 0
    if !reader.readNalUnit(buffer: &sps, count: &spsLength) {
        print("read fail to sps")
        return nil
    }

    var pps: UnsafePointer<UInt8>? = nil
    var ppsLength: Int32 = 0
    
    if !reader.readNalUnit(buffer: &pps, count: &ppsLength) {
        print("read fail to pps")
        return nil
    }
    //print("sps:\(Data(bytes: sps!, count: Int(spsLength)).hexDescription)")
    //print("pps:\(Data(bytes: pps!, count: Int(ppsLength)).hexDescription)")
    var description: CMVideoFormatDescription? = nil
    let  parameterSetPointers : [UnsafePointer<UInt8>] = [sps!, pps!]
    let parameterSetSize: [Int] = [Int(spsLength), Int(ppsLength)]
    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                        parameterSetCount: 2,
                                                        parameterSetPointers: parameterSetPointers,
                                                        parameterSetSizes:
                                                            parameterSetSize,
                                                        nalUnitHeaderLength: 4,
                                                        formatDescriptionOut: &description)
    if status != noErr {
        print("Fail to create video format description.")
        return nil
    }
    return description
}


class H264FormatDescriptor {
    var sps: Data? = nil
    var pps: Data? = nil
    var description: CMVideoFormatDescription? = nil
    
    func configuration(data: UnsafePointer<UInt8>, count: Int) -> Bool {
        var spsPtr: UnsafePointer<UInt8>? = nil
        var spsLength: Int32 = 0
        var ppsPtr: UnsafePointer<UInt8>? = nil
        var ppsLength: Int32 = 0
        if !readParameterSet(data: data, count: count,
                            sps: &spsPtr, spsLength: &spsLength,
                            pps: &ppsPtr, ppsLength: &ppsLength) {
            return false
        }
        
        let other_sps = Data(bytes: spsPtr!, count: Int(spsLength))
        let other_pps = Data(bytes: ppsPtr!, count: Int(ppsLength))
        //이전 sps, pps 정보와 동일하면 변경하지 않음
        if let sps = self.sps, let pps = self.pps {
            if sps == other_sps && pps == other_pps {
                return true
            }
        }
        
        let  parameterSetPointers : [UnsafePointer<UInt8>] = [spsPtr!, ppsPtr!]
        let parameterSetSize: [Int] = [Int(spsLength), Int(ppsLength)]
        
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                            parameterSetCount: 2,
                                                            parameterSetPointers: parameterSetPointers,
                                                            parameterSetSizes:
                                                                parameterSetSize,
                                                            nalUnitHeaderLength: 4,
                                                            formatDescriptionOut: &description)
        if status != noErr {
            print("Fail to create video format description.")
            return false
        }
        //print("H264FormatDescriptor sps:\(other_sps.hexDescription) pps:\(other_pps.hexDescription)")
        self.sps = other_sps
        self.pps = other_pps
        return true 
    }
}
