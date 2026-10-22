#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MARK: - Stitchable shaders used from SwiftUI (fill shaders: half4 name(float2 position, args...))

/// Whole address map in one pass: the fragment finds its cell from `position` and draws a still,
/// rounded tile whose strength follows that address's state. `heat` and `tints` hold one entry per
/// cell, row by row.
[[ stitchable ]] half4 dm_addressMap(float2 position, float4 bounds, float columns, float rows,
                                     device const float *heat, int heatCount,
                                     device const half4 *tints, int tintCount) {
    float2 local = position - bounds.xy;
    float2 cell = bounds.zw / float2(columns, rows);
    int column = int(floor(local.x / cell.x));
    int row = int(floor(local.y / cell.y));
    int index = row * int(columns) + column;
    if (column < 0 || row < 0 || column >= int(columns) || index >= heatCount) {
        return half4(0.0);
    }

    // Rounded-square signed distance in cell space (half-extent normalised to 1).
    float2 uv = fract(local / cell);
    float2 q = abs(uv - 0.5) * 2.0;
    float corner = 0.32;
    float halfSize = 0.84;
    float2 k = max(q - (halfSize - corner), 0.0);
    float distanceToEdge = length(k) - corner;
    float mask = 1.0 - smoothstep(-0.05, 0.05, distanceToEdge);

    float h = clamp(heat[index], 0.0, 1.0);
    half4 tint = index < tintCount ? tints[index] : half4(0.5h, 0.5h, 0.5h, 1.0h);
    float alpha = clamp((0.07 + h * 0.78) * mask, 0.0, 1.0);
    return half4(tint.rgb * half(alpha), half(alpha));
}

// MARK: - Layer effects (half4 name(float2 position, SwiftUI::Layer layer, args...))

/// A soft halo of the layer's own colour: the layer plus 16 samples on two rings around each pixel.
/// `radius` is in points (user space, like `position`); `intensity` scales the halo, 0...1.
/// Premultiplied colours: the halo is composited under the layer, so marks stay crisp.
[[ stitchable ]] half4 dm_glow(float2 position, SwiftUI::Layer layer, float radius, float intensity) {
    half4 base = layer.sample(position);
    half4 halo = half4(0.0h);
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 0.7853981634;
        float2 direction = float2(cos(angle), sin(angle));
        halo += layer.sample(position + direction * radius);
        halo += layer.sample(position + direction * (radius * 0.5));
    }
    halo *= half(intensity / 16.0);
    return base + halo * (1.0h - base.a);
}
