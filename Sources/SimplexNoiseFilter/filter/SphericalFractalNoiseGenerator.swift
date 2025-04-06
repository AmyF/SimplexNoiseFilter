import CoreImage

/// 生成适合映射到3D球体上的分形噪声纹理。
///
/// 使用等距圆柱投影(Equirectangular Projection)生成纹理，
/// 并应用特殊处理以减少极点附近的扭曲。生成的纹理适合用作行星表面。
///
public final class SphericalFractalNoiseGenerator: CIFilter {

    /// 噪声输出中值为`0.0`时使用的颜色。
    public var lowColor: CIColor = .black

    /// 噪声输出中值为`1.0`时使用的颜色。
    public var highColor: CIColor = .white

    /// 沿x轴（经度方向）移动噪声空间的度数。默认值为`0.0`。
    public var offsetX: Float = 0.0

    /// 沿y轴（纬度方向）移动噪声空间的度数。默认值为`0.0`。
    public var offsetY: Float = 0.0

    /// 沿z轴移动噪声空间的距离。默认值为`0.0`。
    public var offsetZ: Float = 0.0

    /// 噪声的"放大"程度。有效值范围为[1...1000]。默认值为`100.0`。
    public var zoom: Float = 100.0

    /// 最终产品中对比度的增加或减少量。默认值为`1.0`。
    public var contrast: Float = 1.0

    /// 生成的噪声八度数。有效值范围为`[1...8]`。默认值为`3`。
    public var octaves: UInt8 = 3

    /// 控制噪声强度。默认值为`1.0`。
    public var amplitude: Float = 1.0

    /// 控制每个八度的大小变化。
    public var lacunarity: Float = 2.0

    /// 控制每个八度对整体值的贡献。
    public var persistence: Float = 0.5

    /// 纹理宽度，默认为1024（2:1宽高比的推荐值）
    public var textureWidth: Float = 1024.0

    /// 纹理高度，默认为512（2:1宽高比的推荐值）
    public var textureHeight: Float = 512.0

    /// 通过从包中加载metallib来设置内核。
    private static var kernel: CIColorKernel? = {
        guard let url = Bundle.module.url(forResource: "SimplexNoise", withExtension: "ci.metallib")
        else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try CIColorKernel(
                functionName: "SphericalFractalNoise3D", fromMetalLibraryData: data)
        } catch {
            print("[ERROR] Failed to create CIColorKernel: \(error)")
        }
        return nil
    }()

    public override var outputImage: CIImage? {
        guard let kernel = SphericalFractalNoiseGenerator.kernel else {
            print("Failed to create kernel.")
            return nil
        }
        return kernel.apply(
            extent: .infinite,
            arguments: [
                lowColor.ciVector,
                highColor.ciVector,
                offsetX,
                offsetY,
                offsetZ,
                max(1.0, min(zoom, 1000.0)),
                max(0.1, min(contrast, 10.0)),
                Float(max(1, min(octaves, 8))),
                amplitude,
                lacunarity,
                persistence,
                textureWidth,
                textureHeight,
            ]
        )
    }
}
