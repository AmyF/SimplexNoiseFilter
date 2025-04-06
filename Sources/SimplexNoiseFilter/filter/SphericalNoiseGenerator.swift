import CoreImage

/// 生成适合映射到3D球体上的2D噪声纹理。
///
/// 使用等距圆柱投影(Equirectangular Projection)生成纹理，
/// 并应用特殊处理以减少极点附近的扭曲。
///
public final class SphericalNoiseGenerator: CIFilter {

    /// 噪声输出中值为`0.0`时使用的颜色。
    public var lowColor: CIColor = .black

    /// 噪声输出中值为`1.0`时使用的颜色。
    public var highColor: CIColor = .white

    /// 沿x轴（经度方向）移动噪声空间的距离。默认值为`0.0`。
    ///
    /// 变化量受`zoom`级别影响。
    public var offsetX: Float = 0.0

    /// 沿y轴（纬度方向）移动噪声空间的距离。默认值为`0.0`。
    ///
    /// 变化量受`zoom`级别影响。
    public var offsetY: Float = 0.0

    /// 沿z轴移动噪声空间的距离。默认值为`0.0`。
    ///
    /// 沿z轴移动会逐渐改变噪声特征的形状，而不会产生明显的水平或垂直移动。
    /// 变化量受`zoom`级别影响。
    public var offsetZ: Float = 0.0

    /// 噪声的"放大"程度。有效值范围为[1...1000]。默认值为`100.0`。
    ///
    /// 值为1.0时，噪声特征非常小。
    public var zoom: Float = 100.0

    /// 最终产品中对比度的增加或减少量。默认值为`1.0`。
    ///
    /// 对比度为1.0是线性对比度。
    /// 对比度在(1 > contrast >= 10)范围内会增加输出的对比度。
    /// 对比度在(0.1 >= contrast > 1)范围内会降低输出的对比度。
    public var contrast: Float = 1.0

    /// 通过从包中加载metallib来设置内核。
    private static var kernel: CIColorKernel? = {
        guard let url = Bundle.module.url(forResource: "SimplexNoise", withExtension: "ci.metallib")
        else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try CIColorKernel(
                functionName: "SphericalSimplexNoise3D", fromMetalLibraryData: data)
        } catch {
            print("[ERROR] Failed to create CIColorKernel: \(error)")
        }
        return nil
    }()

    public override var outputImage: CIImage? {
        guard let kernel = SphericalNoiseGenerator.kernel else {
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
                zoom,
                contrast,
            ]
        )
    }
}
