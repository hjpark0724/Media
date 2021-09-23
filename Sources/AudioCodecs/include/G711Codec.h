
#import <Foundation/Foundation.h>
#import <RTPAudioCodec.h>
typedef NS_ENUM(NSInteger, ConversionMode) {
    LinearToPCMA = 1,
    PCMAToLinear,
    LinearToPCMU,
    PCMUToLinear,
};

@interface G711Codec : NSObject<RTPAudioCodec>
-(instancetype) init:(ConversionMode) mode;
-(NSData*)encode:(NSData*)data;
-(NSData*)decode:(NSData*)data;
@end
