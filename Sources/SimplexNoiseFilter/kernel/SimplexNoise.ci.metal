#include "SimplexNoise.h"
#include <CoreImage/CoreImage.h>
using namespace metal;

// Adapted from C++ source at: https://github.com/SRombauts/SimplexNoise

/**
 * Computes the largest integer value not greater than the float one
 *
 * This method is faster than using (int32_t)std::floor(fp).
 *
 * I measured it to be approximately twice as fast:
 *  float:  ~18.4ns instead of ~39.6ns on an AMD APU),
 *  double: ~20.6ns instead of ~36.6ns on an AMD APU),
 * Reference: http://www.codeproject.com/Tips/700780/Fast-floor-ceiling-functions
 *
 * @param[in] fp    float input value
 *
 * @return largest integer value not greater than fp
 */
static inline int32_t fastfloor(float fp) {
    int32_t i = static_cast<int32_t>(fp);
    return (fp < i) ? (i - 1) : (i);
}

/**
 * Permutation table. This is just a random jumble of all numbers 0-255.
 *
 * This produce a repeatable pattern of 256, but Ken Perlin stated
 * that it is not a problem for graphic texture as the noise features disappear
 * at a distance far enough to be able to see a repeatable pattern of 256.
 *
 * This needs to be exactly the same for all instances on all platforms,
 * so it's easiest to just keep it as static explicit data.
 * This also removes the need for any initialisation of this class.
 *
 * Note that making this an uint32_t[] instead of a uint8_t[] might make the
 * code run faster on platforms with a high penalty for unaligned single
 * byte addressing. Intel x86 is generally single-byte-friendly, but
 * some other CPUs are faster with 4-aligned reads.
 * However, a char[] is smaller, which avoids cache trashing, and that
 * is probably the most important aspect on most architectures.
 * This array is accessed a *lot* by the noise functions.
 * A vector-valued noise over 3D accesses it 96 times, and a
 * float-valued 4D noise 64 times. We want this to fit in the cache!
 */
static constant uint8_t perm[256] = {87, 34, 171, 119, 15, 162, 234, 180, 116, 5, 161, 43, 126, 163, 117, 193, 96, 218, 86, 47, 29, 84, 189, 199, 64, 2, 197, 10, 120, 195, 127, 59, 103, 198, 98, 23, 207, 51, 200, 33, 155, 148, 107, 187, 236, 131, 216, 239, 156, 182, 48, 113, 210, 229, 128, 212, 149, 204, 153, 111, 58, 147, 71, 118, 36, 158, 179, 241, 74, 62, 122, 41, 83, 253, 244, 228, 9, 85, 16, 112, 141, 135, 186, 53, 165, 157, 27, 188, 20, 101, 72, 4, 175, 17, 211, 70, 136, 32, 173, 1, 75, 151, 26, 81, 150, 223, 183, 252, 93, 95, 65, 206, 67, 18, 68, 90, 66, 185, 245, 37, 12, 191, 91, 137, 242, 176, 205, 255, 190, 222, 220, 77, 250, 196, 177, 134, 192, 168, 133, 19, 94, 45, 219, 164, 60, 170, 208, 221, 217, 154, 194, 159, 169, 55, 209, 8, 61, 76, 146, 22, 240, 246, 184, 152, 167, 144, 3, 106, 99, 109, 50, 233, 115, 238, 110, 44, 174, 108, 249, 31, 54, 97, 121, 69, 202, 56, 105, 251, 237, 57, 224, 226, 203, 247, 104, 30, 140, 7, 132, 11, 49, 40, 24, 129, 139, 227, 166, 143, 231, 82, 14, 46, 28, 39, 13, 172, 124, 138, 73, 178, 160, 0, 142, 88, 213, 230, 130, 78, 243, 125, 145, 181, 215, 232, 201, 89, 92, 102, 25, 235, 248, 42, 79, 254, 114, 123, 214, 35, 38, 63, 225, 21, 52, 100, 6, 80};

/**
 * Helper function to hash an integer using the above permutation table
 *
 *  This inline function costs around 1ns, and is called N+1 times for a noise of N dimension.
 *
 *  Using a real hash function would be better to improve the "repeatability of 256" of the above permutation table,
 * but fast integer Hash functions uses more time and have bad random properties.
 *
 * @param[in] i Integer value to hash
 *
 * @return 8-bits hashed value
 */
static inline uint8_t hash(int32_t i) {
    return perm[static_cast<uint8_t>(i)];
}

/**
 * Helper functions to compute gradients-dot-residual vectors (3D)
 *
 * @param[in] hash  hash value
 * @param[in] x     x coord of the distance to the corner
 * @param[in] y     y coord of the distance to the corner
 * @param[in] z     z coord of the distance to the corner
 *
 * @return gradient value
 */
static float grad(int32_t hash, float x, float y, float z) {
    int h = hash & 15;     // Convert low 4 bits of hash code into 12 simple
    float u = h < 8 ? x : y; // gradient directions, and compute dot product.
    float v = h < 4 ? y : h == 12 || h == 14 ? x : z; // Fix repeats at h = 12 to 15
    return ((h & 1) ? -u : u) + ((h & 2) ? -v : v);
}

/**
 * 3D Perlin simplex noise
 *
 * @param[in] x float coordinate
 * @param[in] y float coordinate
 * @param[in] z float coordinate
 *
 * @return Noise value in the range[-1; 1], value of 0 on all integer coordinates.
 */
float SimplexNoise::noise(float x, float y, float z) {
    float n0, n1, n2, n3; // Noise contributions from the four corners

    // Skewing/Unskewing factors for 3D
    const float F3 = 1.0f / 3.0f;
    const float G3 = 1.0f / 6.0f;

    // Skew the input space to determine which simplex cell we're in
    float s = (x + y + z) * F3; // Very nice and simple skew factor for 3D
    int i = fastfloor(x + s);
    int j = fastfloor(y + s);
    int k = fastfloor(z + s);
    float t = (i + j + k) * G3;
    float X0 = i - t; // Unskew the cell origin back to (x,y,z) space
    float Y0 = j - t;
    float Z0 = k - t;
    float x0 = x - X0; // The x,y,z distances from the cell origin
    float y0 = y - Y0;
    float z0 = z - Z0;

    // For the 3D case, the simplex shape is a slightly irregular tetrahedron.
    // Determine which simplex we are in.
    int i1, j1, k1; // Offsets for second corner of simplex in (i,j,k) coords
    int i2, j2, k2; // Offsets for third corner of simplex in (i,j,k) coords
    if (x0 >= y0) {
        if (y0 >= z0) {
            i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0; // X Y Z order
        } else if (x0 >= z0) {
            i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1; // X Z Y order
        } else {
            i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1; // Z X Y order
        }
    } else { // x0<y0
        if (y0 < z0) {
            i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1; // Z Y X order
        } else if (x0 < z0) {
            i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1; // Y Z X order
        } else {
            i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0; // Y X Z order
        }
    }

    // A step of (1,0,0) in (i,j,k) means a step of (1-c,-c,-c) in (x,y,z),
    // a step of (0,1,0) in (i,j,k) means a step of (-c,1-c,-c) in (x,y,z), and
    // a step of (0,0,1) in (i,j,k) means a step of (-c,-c,1-c) in (x,y,z), where
    // c = 1/6.
    float x1 = x0 - i1 + G3; // Offsets for second corner in (x,y,z) coords
    float y1 = y0 - j1 + G3;
    float z1 = z0 - k1 + G3;
    float x2 = x0 - i2 + 2.0f * G3; // Offsets for third corner in (x,y,z) coords
    float y2 = y0 - j2 + 2.0f * G3;
    float z2 = z0 - k2 + 2.0f * G3;
    float x3 = x0 - 1.0f + 3.0f * G3; // Offsets for last corner in (x,y,z) coords
    float y3 = y0 - 1.0f + 3.0f * G3;
    float z3 = z0 - 1.0f + 3.0f * G3;

    // Work out the hashed gradient indices of the four simplex corners
    int gi0 = hash(i + hash(j + hash(k)));
    int gi1 = hash(i + i1 + hash(j + j1 + hash(k + k1)));
    int gi2 = hash(i + i2 + hash(j + j2 + hash(k + k2)));
    int gi3 = hash(i + 1 + hash(j + 1 + hash(k + 1)));

    // Calculate the contribution from the four corners
    float t0 = 0.6f - x0*x0 - y0*y0 - z0*z0;
    if (t0 < 0) {
        n0 = 0.0;
    } else {
        t0 *= t0;
        n0 = t0 * t0 * grad(gi0, x0, y0, z0);
    }
    float t1 = 0.6f - x1*x1 - y1*y1 - z1*z1;
    if (t1 < 0) {
        n1 = 0.0;
    } else {
        t1 *= t1;
        n1 = t1 * t1 * grad(gi1, x1, y1, z1);
    }
    float t2 = 0.6f - x2*x2 - y2*y2 - z2*z2;
    if (t2 < 0) {
        n2 = 0.0;
    } else {
        t2 *= t2;
        n2 = t2 * t2 * grad(gi2, x2, y2, z2);
    }
    float t3 = 0.6f - x3*x3 - y3*y3 - z3*z3;
    if (t3 < 0) {
        n3 = 0.0;
    } else {
        t3 *= t3;
        n3 = t3 * t3 * grad(gi3, x3, y3, z3);
    }
    // Add contributions from each corner to get the final noise value.
    // The result is scaled to stay just inside [-1,1]
    return 32.0f*(n0 + n1 + n2 + n3);
}

/**
 * Fractal/Fractional Brownian Motion (fBm) summation of 3D Perlin Simplex noise
 *
 * @param[in] octaves   number of fraction of noise to sum
 * @param[in] x         float coordinate
 * @param[in] y         float coordinate
 * @param[in] z         float coordinate
 * @param[in] freq      noise frequency
 * @param[in] amp       noise amplitude
 * @param[in] lac       lacuniarity
 * @param[in] per       persistence
 *
 * @return Noise value in the range[-1; 1], value of 0 on all integer coordinates.
 */
float SimplexNoise::fractal(size_t octaves, float x, float y, float z, float freq, float amp, float lac, float per) {
    float output = 0.f;
    float denom  = 0.f;

    for (size_t i = 0; i < octaves; i++) {
        output += (amp * noise(x * freq, y * freq, z * freq));
        denom += amp;

        freq *= lac;
        amp *= per;
    }

    return (output / denom);

}

extern "C" float4 SimplexNoise3D(float4 lowColor, float4 highColor, float offsetX, float offsetY, float offsetZ, float zoom, float contrast, coreimage::destination dest) {

    // Apply offsets in scaling.
    float x = (dest.coord().x + offsetX) / zoom;
    float y = (dest.coord().y + offsetY) / zoom;
    float z = offsetZ / zoom;

    // Calculate noise value and normalize to the range [0, 1]
    float val = (SimplexNoise::noise(x, y, z) + 1.0) / 2.0;

    // A contrast of 1.0 applies no transformation to the noise function, so we can just return it now.
    if (contrast == 1.0) { return mix(lowColor, highColor, val); }

    // The sigmoid function breaks down at exactly 0.0 and 1.0, so we just return the expected values there.
    if (val == 0.0) { return lowColor; }
    if (val == 1.0) { return highColor; }

    // Apply the sigmoid function.
    float cVal = 1 / (1 + pow(val / (1 - val), -contrast));

    // Return the mixed color value.
    return mix(lowColor, highColor, cVal);
}

extern "C" float4 FractalNoise3D(float4 lowColor, float4 highColor, float offsetX, float offsetY, float offsetZ, float zoom, float contrast, float octaves, float amplitude, float lacuniarity, float persistence, coreimage::destination dest) {

    // Apply offsets and scaling.
    float x = dest.coord().x + offsetX;
    float y = dest.coord().y + offsetY;
    size_t oct = (size_t) octaves;

    // Calculate the noise value and normalize the result to the range [0, 1].
    float val = (SimplexNoise::fractal(oct, x, y, offsetZ, 1.0 / zoom, amplitude, lacuniarity, persistence) + 1.0) / 2.0;

    // A contrast of 1.0 applies no transformation to the noise function, so we can just return it now.
    if (contrast == 1.0) { return mix(lowColor, highColor, val); }

    // The sigmoid function breaks down at exactly 0.0 and 1.0, so we just return the expected values there.
    if (val == 0.0) { return lowColor; }
    if (val == 1.0) { return highColor; }

    // Apply the sigmoid function to adjust contrast.
    float cVal = 1 / (1 + pow(val / (1 - val), -contrast));

    // Return the mixed color value.
    return mix(lowColor, highColor, cVal);
}

extern "C" float4 SphericalSimplexNoise3D(float4 lowColor, float4 highColor, float offsetX, float offsetY, float offsetZ, float zoom, float contrast, float width, float height, coreimage::destination dest) {
    // 获取当前像素坐标
    float x = dest.coord().x;
    float y = dest.coord().y;
    
    // 将像素坐标归一化到[0,1]范围
    // 我们需要传入纹理的宽度和高度作为参数
    float u = x / width;
    float v = y / height;
    
    // 转换为球面坐标 (theta, phi)
    float theta = 2.0f * M_PI_F * u + offsetX / zoom; // 经度 [0, 2π]
    float phi = M_PI_F * v - M_PI_F / 2.0f + offsetY / zoom; // 纬度 [-π/2, π/2]
    
    // 转换为3D笛卡尔坐标
    float sampleX = cos(phi) * cos(theta);
    float sampleY = cos(phi) * sin(theta);
    float sampleZ = sin(phi) + offsetZ / zoom;
    
    // 处理极点扭曲
    float polarThreshold = 0.7f; // sin(phi) > 0.7 约等于纬度 > 45度
    float noiseValue;
    
    if (abs(sin(phi)) > polarThreshold) {
        // 在极点附近使用多重采样
        float noiseSum = 0.0f;
        int samples = 8;
        float polarWeight = (1.0f - abs(sin(phi))) / (1.0f - polarThreshold);
        
        for (int i = 0; i < samples; i++) {
            float sampleTheta = theta + (2.0f * M_PI_F * i) / samples;
            float x1 = cos(phi) * cos(sampleTheta);
            float y1 = cos(phi) * sin(sampleTheta);
            float z1 = sin(phi) + offsetZ / zoom;
            
            noiseSum += SimplexNoise::noise(x1 * zoom, y1 * zoom, z1 * zoom);
        }
        
        // 混合多重采样结果和单点采样结果
        float singleSampleNoise = SimplexNoise::noise(sampleX * zoom, sampleY * zoom, sampleZ * zoom);
        noiseValue = mix(noiseSum / samples, singleSampleNoise, polarWeight);
    } else {
        // 正常区域使用标准采样
        noiseValue = SimplexNoise::noise(sampleX * zoom, sampleY * zoom, sampleZ * zoom);
    }
    
    // 归一化到[0,1]范围
    noiseValue = (noiseValue + 1.0f) / 2.0f;
    
    // 应用对比度调整
    if (contrast == 1.0f) { return mix(lowColor, highColor, noiseValue); }
    if (noiseValue == 0.0f) { return lowColor; }
    if (noiseValue == 1.0f) { return highColor; }
    
    // 应用sigmoid函数调整对比度
    float cVal = 1.0f / (1.0f + pow(noiseValue / (1.0f - noiseValue), -contrast));
    
    // 返回混合颜色值
    return mix(lowColor, highColor, cVal);
}

extern "C" float4 SphericalFractalNoise3D(
    float4 lowColor,
    float4 highColor,
    float offsetX,
    float offsetY,
    float offsetZ,
    float zoom,
    float contrast,
    float octaves,
    float amplitude,
    float lacunarity,  // 修正拼写
    float persistence,
    float width,
    float height,
    coreimage::destination dest
) {
    // 获取当前像素坐标
    float x = dest.coord().x;
    float y = dest.coord().y;
    
    // 将像素坐标归一化到[0,1]范围
    float u = x / width;
    float v = y / height;
    
    // 转换为球面坐标 (theta, phi)
    float theta = 2.0f * M_PI_F * u + offsetX * (M_PI_F / 180.0f);
    float phi = M_PI_F * v - M_PI_F / 2.0f + offsetY * (M_PI_F / 180.0f);
    
    // 转换为3D笛卡尔坐标（单位球面上的点）
    const float earthRadius = 1.0f;
    float radius = earthRadius + offsetZ / 100.0f;
    float xyRadius = radius * cos(phi);
    float sampleX = xyRadius * cos(theta);
    float sampleY = xyRadius * sin(theta);
    float sampleZ = radius * sin(phi);
    
    // 处理极点区域
    float polarThreshold = 0.95f; // 仅处理极圈附近
    float noiseValue = 0.0f;
    
    // 计算分形噪声
    int oct = int(octaves);
    if (abs(sin(phi)) > polarThreshold) {
        // 极点区域多重采样
        float noiseSum = 0.0f;
        int samples = 2;
        float polarWeight = smoothstep(0.0f, 1.0f,
            (1.0f - abs(sin(phi))) / (1.0f - polarThreshold));
        
        for (int i = 0; i < samples; i++) {
            float sampleTheta = theta + (2.0f * M_PI_F * i) / samples;
            float x1 = xyRadius * cos(sampleTheta);
            float y1 = xyRadius * sin(sampleTheta);
            
            noiseSum += SimplexNoise::fractal(
                oct,
                x1 * zoom,  // x
                y1 * zoom,  // y
                sampleZ * zoom,  // z
                1.0f,       // freq (频率参数)
                amplitude,   // amp (振幅)
                lacunarity,  // lac (间隙度)
                persistence  // per (持久度)
            );
        }
        // 单点采样调用
        float singleSample = SimplexNoise::fractal(
            oct,
            sampleX * zoom,
            sampleY * zoom,
            sampleZ * zoom,
            1.0f,      // 新增频率参数
            amplitude,
            lacunarity,
            persistence
        );
        noiseValue = mix(noiseSum / samples, singleSample, polarWeight);
    } else {
        // 正常区域
        noiseValue = SimplexNoise::fractal(
            oct,
            sampleX * zoom,
            sampleY * zoom,
            sampleZ * zoom,
            1.0f,      // 新增频率参数
            amplitude,
            lacunarity,
            persistence
        );
    }
    
    // 确保噪声值在[-1, 1]范围
    noiseValue = clamp(noiseValue, -1.0f, 1.0f);
    
    // 归一化到[0,1]范围
    noiseValue = (noiseValue + 1.0f) / 2.0f;
    
    // 应用对比度调整
    if (contrast == 1.0f) return mix(lowColor, highColor, noiseValue);
    if (noiseValue <= 0.0f) return lowColor;
    if (noiseValue >= 1.0f) return highColor;
    
    // 使用更安全的sigmoid计算
    float safeNoise = max(0.0001f, min(0.9999f, noiseValue));
    float cVal = 1.0f / (1.0f + pow(safeNoise / (1.0f - safeNoise), -contrast));
    
    return mix(lowColor, highColor, cVal);
}