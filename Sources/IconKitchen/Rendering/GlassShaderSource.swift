/// The Liquid-Glass fragment shader, compiled at runtime via
/// `device.makeLibrary(source:)`. Kept as a Swift string so it works
/// reliably from a SwiftPM executable without a resource bundle.
enum GlassShaderSource {
    static let metal = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 resolution;
        float  lightAngle;
        float  time;
        float4 colorTop;
        float4 colorBottom;
        float  scale;
        float  cornerCurvature;
        float  specular;
        float  edgeGlow;
        float  depth;
        float  viewScale;      // canvas zoom (1 == fit)
        float2 viewOffset;     // canvas pan, in pixels
        float  appearance;     // 0 default, 1 dark, 2 clear, 3 tinted
        float  _p0; float _p1; float _p2;
    };

    // Remaps a layer's color for the selected appearance variant. isBase == 1 for
    // the glass tile, 0 for image elements (which stay light in dark mode).
    static inline float3 apply_appearance(float3 c, float mode, float isBase) {
        if (mode < 0.5) return c;                                     // default
        float lum = dot(c, float3(0.299, 0.587, 0.114));
        if (mode < 1.5) {                                            // dark
            if (isBase > 0.5) {
                float t = smoothstep(0.30, 0.68, lum);
                return mix(float3(0.05, 0.05, 0.06), float3(0.28, 0.29, 0.33), t);
            }
            return c;                                               // elements keep color
        }
        if (mode < 2.5) return mix(float3(lum), float3(0.88), 0.35); // clear
        return float3(0.30, 0.45, 0.85) * (0.35 + 0.9 * lum);       // tinted
    }

    struct VSOut {
        float4 position [[position]];
        float2 frag;
    };

    vertex VSOut glass_vertex(uint vid [[vertex_id]],
                              constant Uniforms &u [[buffer(0)]]) {
        float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        VSOut out;
        out.position = float4(pos[vid], 0, 1);
        float2 uv = pos[vid] * 0.5 + 0.5;
        out.frag = float2(uv.x, 1.0 - uv.y) * u.resolution;
        return out;
    }

    static inline float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    // Smooth value noise (bilinearly interpolated hash) for soft tonal variation.
    static inline float vnoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1, 0));
        float c = hash21(i + float2(0, 1));
        float d = hash21(i + float2(1, 1));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    // Signed distance to a rounded rectangle with STRAIGHT sides. The corner
    // uses a p-norm: power == 2 is a circular arc, power > 2 gives Apple's
    // continuous-curvature ("squircle") corner. Negative inside, 0 on the edge.
    static inline float sdRoundedBox(float2 p, float2 b, float r, float power) {
        float2 q = abs(p) - b + r;
        float2 m = max(q, float2(0.0));
        float corner = pow(pow(m.x, power) + pow(m.y, power), 1.0 / power);
        return corner + min(max(q.x, q.y), 0.0) - r;
    }

    fragment float4 glass_fragment(VSOut in [[stage_in]],
                                   constant Uniforms &u [[buffer(0)]]) {
        float minDim = min(u.resolution.x, u.resolution.y);
        float2 center = 0.5 * u.resolution + u.viewOffset;
        float2 c = (in.frag - center) / (0.5 * minDim * u.viewScale);

        // Rounded rectangle with straight sides. cornerCurvature is reused as the
        // corner p-norm power (>2 == continuous "squircle" corner).
        float S = u.scale;
        float2 b = float2(S);
        float r = 0.45 * S;                       // corner radius, iOS-like
        float power = max(u.cornerCurvature * 0.5, 2.0);
        float sdf = sdRoundedBox(c, b, r, power);

        // Soft ambient drop shadow — wide and diffuse with a slight downward
        // bias, like Apple's, not a dark tight contact shadow.
        float2 shadowOffset = float2(0.0, 0.022 * (1.0 + u.depth));
        float shBlur = 0.10 + 0.10 * u.depth;
        float shSdf = sdRoundedBox(c - shadowOffset, b, r, power);
        float shadow = (1.0 - smoothstep(-shBlur, shBlur, shSdf)) * 0.22;

        float aa = max(fwidth(sdf), 1e-4);
        float coverage = 1.0 - smoothstep(-aa, aa, sdf);

        // FLAT glass slab. The edge is a soft, wide LUMINOUS rim — the blue
        // gets lighter near the boundary and gently bleeds outward — NOT a 3D
        // bevel (no bright-rim / dark-groove structure).
        float aH = (u.lightAngle - 45.0) * 3.14159265 / 180.0;
        float2 H = float2(cos(aH), sin(aH));

        // Base albedo: rich blue, gentle top-lighter gradient.
        float tv = clamp(0.5 - 0.30 * (c.y / S), 0.0, 1.0);
        float3 albedo = mix(u.colorBottom.rgb, u.colorTop.rgb, tv);
        float3 edgeTint = float3(0.80, 0.90, 1.0);

        float3 col = albedo;

        // Narrow rim band hugging just inside the (crisp) edge. DIRECTIONAL:
        // bright on the lit (top) side, fading to nothing down the sides, and a
        // faint dark edge on the unlit (bottom) side — flat glass lit from above.
        float edgeDist = -sdf;                                  // 0 at edge, + inside
        float rimBand = pow(clamp(1.0 - smoothstep(0.0, 0.08 * S, edgeDist), 0.0, 1.0), 1.6);
        float facing = clamp(dot(normalize(c + float2(1e-6)), H), -1.0, 1.0);
        float litSide = clamp(facing, 0.0, 1.0);               // 1 top -> 0 sides
        float darkSide = clamp(-facing, 0.0, 1.0);             // 1 bottom -> 0 sides
        col = mix(col, edgeTint, rimBand * litSide * (0.32 + 0.16 * u.edgeGlow));
        col *= 1.0 - rimBand * darkSide * 0.10;                // subtle bottom-edge shade

        // Surface detail, anchored to the icon so it zooms WITH the material:
        // soft low-frequency tonal variation (organic depth) + fine grain (kills
        // banding, gives real texture when magnified).
        float2 sc = c / S;
        float macro = (vnoise(sc * 7.0) - 0.5) * 0.020;
        float grain = (hash21(c * 620.0) - 0.5) * 0.012;
        col += macro + grain;
        col = apply_appearance(col, u.appearance, 1.0);
        col = clamp(col, 0.0, 1.0);

        // No outer bloom — the outer boundary stays crisp (just anti-aliased).
        float bloom = 0.0;
        float3 hlTint = edgeTint;

        // Composite shadow (back) -> bloom -> slab (front), premultiplied.
        float slabA = coverage;
        float A1 = bloom + shadow * (1.0 - bloom);
        float3 C1 = hlTint * bloom;
        float outA = slabA + A1 * (1.0 - slabA);
        float3 pm = col * slabA + C1 * (1.0 - slabA);
        return float4(pm, outA);
    }

    // ---- Image element pipeline ----

    struct ImageUniforms {
        float2 resolution;
        float  viewScale;
        float  baseScale;      // squircle mask half-extent
        float2 viewOffset;
        float2 elemOffset;     // element position (canvas units)
        float  elemScale;      // element half-extent
        float  elemRotation;   // radians
        float  cornerPower;    // squircle p-norm power
        float  elemDepth;      // how far the element floats (drives its shadow)
        float  lightAngle;     // degrees, for the element's edge lighting
        float  appearance;     // 0 default, 1 dark, 2 clear, 3 tinted
    };

    // Element coverage (texture alpha) at a canvas point, in element-local space.
    static inline float elem_alpha(float2 cc, constant ImageUniforms &u,
                                   texture2d<float> tex, sampler samp) {
        float2 p = cc - u.elemOffset;
        float cs = cos(-u.elemRotation), sn = sin(-u.elemRotation);
        p = float2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
        float2 uv = p / u.elemScale * 0.5 + 0.5;
        float inb = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
        return tex.sample(samp, clamp(uv, 0.0, 1.0), level(0)).a * inb;
    }

    vertex VSOut image_vertex(uint vid [[vertex_id]],
                              constant ImageUniforms &u [[buffer(0)]]) {
        float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        VSOut out;
        out.position = float4(pos[vid], 0, 1);
        float2 uv = pos[vid] * 0.5 + 0.5;
        out.frag = float2(uv.x, 1.0 - uv.y) * u.resolution;
        return out;
    }

    fragment float4 image_fragment(VSOut in [[stage_in]],
                                   constant ImageUniforms &u [[buffer(0)]],
                                   texture2d<float> tex [[texture(0)]],
                                   sampler samp [[sampler(0)]]) {
        float minDim = min(u.resolution.x, u.resolution.y);
        float2 center = 0.5 * u.resolution + u.viewOffset;
        float2 c = (in.frag - center) / (0.5 * minDim * u.viewScale);

        // Into element-local space: translate, un-rotate, scale to [0,1] uv.
        float2 p = c - u.elemOffset;
        float cs = cos(-u.elemRotation), sn = sin(-u.elemRotation);
        p = float2(p.x * cs - p.y * sn, p.x * sn + p.y * cs);
        float2 uv = p / u.elemScale * 0.5 + 0.5;

        float inb = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
        float4 texel = tex.sample(samp, clamp(uv, 0.0, 1.0), level(0)) * inb;   // premultiplied

        // --- Glass material on the element silhouette ---
        // Soft coverage + edge normal from the alpha field give soft glass edges
        // and a directional rim light, like the base tile. Small step = crisp,
        // thin rim (a wide step reads as a chunky band).
        float e = 0.0035;
        float aC  = elem_alpha(c, u, tex, samp);
        float aR  = elem_alpha(c + float2(e, 0), u, tex, samp);
        float aL  = elem_alpha(c - float2(e, 0), u, tex, samp);
        float aU  = elem_alpha(c + float2(0, e), u, tex, samp);
        float aD  = elem_alpha(c - float2(0, e), u, tex, samp);
        float aRU = elem_alpha(c + float2(e, e), u, tex, samp);
        float aLU = elem_alpha(c + float2(-e, e), u, tex, samp);
        float aRD = elem_alpha(c + float2(e, -e), u, tex, samp);
        float aLD = elem_alpha(c + float2(-e, -e), u, tex, samp);
        float cov = (aC * 4.0 + (aR + aL + aU + aD) * 2.0 + (aRU + aLU + aRD + aLD)) / 16.0;
        float2 grad = float2(aR - aL, aU - aD);
        float2 outward = normalize(-grad + float2(1e-6));
        float edgeBand = clamp(4.0 * cov * (1.0 - cov), 0.0, 1.0);

        float aH = (u.lightAngle - 45.0) * 3.14159265 / 180.0;
        float2 H = float2(cos(aH), sin(aH));
        float lf = dot(outward, H);

        float3 fill = texel.a > 0.001 ? texel.rgb / texel.a : float3(1.0);
        float3 white = float3(1.0);
        fill += white * edgeBand * clamp(lf, 0.0, 1.0) * 0.55;    // lit rim
        fill *= 1.0 - edgeBand * clamp(-lf, 0.0, 1.0) * 0.12;     // far-edge shade
        fill = apply_appearance(fill, u.appearance, 0.0);
        fill = clamp(fill, 0.0, 1.0);

        // Very subtle, tight contact shadow — Apple's layered elements barely
        // cast one. Small offset + small blur so it hugs the silhouette.
        float2 shOff = float2(0.0, 0.006 + 0.014 * u.elemDepth);
        float blur = 0.008 + 0.012 * u.elemDepth;
        float2 scc = c - shOff;
        float sh = elem_alpha(scc, u, tex, samp);
        for (int i = 0; i < 12; i++) {
            float a = float(i) * (6.2831853 / 12.0);
            sh += elem_alpha(scc + blur * float2(cos(a), sin(a)), u, tex, samp);
        }
        sh /= 13.0;

        // Mask everything to the base squircle.
        float baseSdf = sdRoundedBox(c, float2(u.baseScale), 0.45 * u.baseScale,
                                     max(u.cornerPower, 2.0));
        float aaM = max(fwidth(baseSdf), 1e-4);
        float mask = 1.0 - smoothstep(-aaM, aaM, baseSdf);

        float fillA = cov * mask;
        float shadowA = sh * mask * 0.12;
        float outA = fillA + shadowA * (1.0 - fillA);   // element over black shadow
        return float4(fill * fillA, outA);
    }
    """
}
