//
//  RTPAudioCodec.h
//  
//
//  Created by HYEONJUN PARK on 2021/05/17.
//

typedef NS_ENUM(NSInteger, AudioCodecType) {
    g711,
    amrwb,
};

@protocol RTPAudioCodec <NSObject>
@required
@property (readonly) AudioCodecType codecType;
-(NSData*)encode:(NSData*)data;
-(NSData*)decode:(NSData*)data;
@end
