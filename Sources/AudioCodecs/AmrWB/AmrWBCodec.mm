//
//  AmrWBCodec.m
//  
//
//  Created by HYEONJUN PARK on 2020/12/24.
//

#import <Foundation/Foundation.h>
#include "amrwb_codec.h"
#include "RTPAudioCodec.h"
#include <iostream>
#include <memory>
@interface AmrWBCodec : NSObject<RTPAudioCodec> {
    std::unique_ptr<CAmrwb> codec;
    int mode;
}

@end

@implementation AmrWBCodec
typedef NS_ENUM(NSInteger, BitrateMode) {
    BitrateModeMode_7k,
    BitrateModeMode_9k,
    BitrateModeMode_12k,
    BitrateModeMode_14k,
    BitrateModeMode_16k,
    BitrateModeMode_18k,
    BitrateModeMode_20k,
    BitrateModeMode_23k,
    BitrateModeMode_24k,
};
@synthesize codecType;
-(instancetype) init:(BitrateMode) bitmode {
    if( self = [super init] ) {
        mode = (int)bitmode;
        codecType = amrwb;
        codec = std::make_unique<CAmrwb>();
        codec->InitCodec();
    }
    return self;
}

-(void)dealloc {
    if(codec) {
        codec->CloseCodec();
    }
}

-(NSData*)encode:(NSData*)data {
    int length = [self encodedDataLength:(BitrateMode)mode];
    auto packets = std::make_unique<uint8_t[]>(length);
    codec->Encode((uint8_t*)data.bytes, packets.get(), mode);
    return [NSData dataWithBytes:packets.get() length:length];
}


-(NSData*)decode:(NSData*)data {
    auto decodedData = std::make_unique<uint8_t[]>(640);
    codec->Decode((uint8_t*)data.bytes, decodedData.get());
    return [NSData dataWithBytes:decodedData.get() length:640];
}


-(int)encodedDataLength:(BitrateMode)mode {
    switch (mode) {
    case BitrateModeMode_7k: return 18; //(nb_bits/8) + header(1) + padding(1)
    case BitrateModeMode_9k: return 24;
    case BitrateModeMode_12k: return 33;
    case BitrateModeMode_14k: return 37;
    case BitrateModeMode_16k: return 41;
    case BitrateModeMode_18k: return 47;
    case BitrateModeMode_20k: return 51;
    case BitrateModeMode_23k: return 59;
    case BitrateModeMode_24k: return 61;
    }
}
@end
