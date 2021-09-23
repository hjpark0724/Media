#include <stdlib.h>
#include "libyuv/convert_scale.h"
#include "libyuv/video_common.h"
#include "libyuv/planar_functions.h"
#include "libyuv/scale.h"
#ifdef __cplusplus
namespace libyuv {
extern "C" {
#endif

LIBYUV_API
int NV12ToI420Scale(const uint8_t* src_y,
                    int src_stride_y,
                    const uint8_t* src_uv,
                    int src_stride_uv,
                    int src_width,
                    int src_height,
                    uint8_t* dst_y,
                    int dst_stride_y,
                    uint8_t* dst_u,
                    int dst_stride_u,
                    uint8_t* dst_v,
                    int dst_stride_v,
                    int dst_width,
                    int dst_height) {
    if(src_width == dst_width && src_height == dst_height) {
        NV12ToI420(src_y, src_stride_y, src_uv, src_stride_uv, dst_y, dst_stride_y, dst_u, dst_stride_u, dst_v, dst_stride_v, src_width, src_height);
        return 0;
    }
    const int src_uv_width = (src_width + 1) / 2;
    const int src_uv_height = (src_height + 1) / 2;
    uint8_t* temp = (uint8_t*)malloc(src_uv_width * src_uv_height * 2);
    uint8_t* src_u = temp;
    uint8_t* src_v = temp + src_uv_width * src_uv_height;
    SplitUVPlane(src_uv, src_stride_uv, src_u, src_uv_width, src_v, src_uv_width, src_uv_width, src_uv_height);
    int ret =  I420Scale(src_y, src_stride_y, src_u, src_uv_width, src_v, src_uv_width, src_width, src_height, dst_y, dst_stride_y, dst_u, dst_stride_u, dst_v, dst_stride_v, dst_width, dst_height, kFilterBox);
    free(temp);
    return ret;
}


#ifdef __cplusplus
}  // extern "C"
}  // namespace libyuv
#endif
