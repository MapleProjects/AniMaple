// AniMaple — pipeline de mejora y recuperación de detalles
// 1) deband_ext: suavizado bilateral de gradientes y dither TPDF 10-12 bit
// 2) dering: supresión de ringing y mosquito noise por compresión DCT/MDCT
// 3) line_reconstruction: recuperación de contraste de lineart y mitigación de chroma blur 4:2:0
// 4) AMD FSR 1.0 EASU: reconstrucción direccional de bordes y reescalado a OUTPUT
// 5) AMD FSR 1.0 RCAS: afilado adaptativo de contraste con atenuación de ruido
// 6) AMD CAS: afilado adaptativo fino post-upscale
// 7) FXAA final: anti-aliasing de aristas residuales al final de la cadena

// Advanced Gradient Smoothing and Bit-Depth Band Extension Shader
// Removes 8-bit quantization steps, color banding and compression contouring
//!HOOK MAIN
//!BIND HOOKED
//!SAVE DEBTEX
//!DESC Advanced Gradient Bit-Depth Band Smoothing & Dither

#define THRESHOLD 0.03
#define RANGE 12.0
#define GRAIN 0.002

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float tpdf(vec2 p) {
    float r1 = hash(p);
    float r2 = hash(p + vec2(1.337, 7.331));
    return (r1 + r2 - 1.0);
}

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec2 pt = HOOKED_pt;

    vec3 avg = vec3(0.0);
    float total_w = 0.0;

    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 0.78539816;
        vec2 dir = vec2(cos(angle), sin(angle));
        vec4 sample_c = HOOKED_tex(HOOKED_pos + dir * pt * RANGE);
        vec3 diff = abs(sample_c.rgb - c.rgb);

        float max_diff = max(max(diff.r, diff.g), diff.b);
        if (max_diff < THRESHOLD) {
            float w = 1.0 - (max_diff / THRESHOLD);
            avg += sample_c.rgb * w;
            total_w += w;
        }
    }

    vec3 smoothed = c.rgb;
    if (total_w > 0.001) {
        smoothed = avg / total_w;
    }

    // High frequency TPDF dither to expand to 10-12 bit gradients
    float d = tpdf(HOOKED_pos * 1000.0) * GRAIN;
    vec3 result = clamp(smoothed + vec3(d), 0.0, 1.0);

    return vec4(result, c.a);
}

// Pass 2: Compression Ringing & Mosquito Noise Reduction
//!HOOK MAIN
//!BIND DEBTEX
//!SAVE DERINGTEX
//!DESC Compression Ringing & Mosquito Artifact Suppression

vec4 hook() {
    vec4 c = DEBTEX_tex(DEBTEX_pos);
    vec2 pt = DEBTEX_pt;
    vec3 luma_w = vec3(0.2627, 0.6780, 0.0593);

    // Sample 3x3 neighborhood
    vec3 cNW = DEBTEX_tex(DEBTEX_pos + vec2(-pt.x, -pt.y)).rgb;
    vec3 cN  = DEBTEX_tex(DEBTEX_pos + vec2(0.0,   -pt.y)).rgb;
    vec3 cNE = DEBTEX_tex(DEBTEX_pos + vec2( pt.x, -pt.y)).rgb;
    vec3 cW  = DEBTEX_tex(DEBTEX_pos + vec2(-pt.x, 0.0)).rgb;
    vec3 cM  = c.rgb;
    vec3 cE  = DEBTEX_tex(DEBTEX_pos + vec2( pt.x, 0.0)).rgb;
    vec3 cSW = DEBTEX_tex(DEBTEX_pos + vec2(-pt.x,  pt.y)).rgb;
    vec3 cS  = DEBTEX_tex(DEBTEX_pos + vec2(0.0,    pt.y)).rgb;
    vec3 cSE = DEBTEX_tex(DEBTEX_pos + vec2( pt.x,  pt.y)).rgb;

    float lNW = dot(cNW, luma_w);
    float lN  = dot(cN,  luma_w);
    float lNE = dot(cNE, luma_w);
    float lW  = dot(cW,  luma_w);
    float lM  = dot(cM,  luma_w);
    float lE  = dot(cE,  luma_w);
    float lSW = dot(cSW, luma_w);
    float lS  = dot(cS,  luma_w);
    float lSE = dot(cSE, luma_w);

    // Neighborhood bounding
    float crossMin = min(min(lN, lS), min(lW, lE));
    float crossMax = max(max(lN, lS), max(lW, lE));
    float diagMin = min(min(lNW, lNE), min(lSW, lSE));
    float diagMax = max(max(lNW, lNE), max(lSW, lSE));

    float localMin = min(crossMin, diagMin);
    float localMax = max(crossMax, diagMax);

    float clampedLuma = clamp(lM, localMin, localMax);
    float diff = clampedLuma - lM;

    float edgeIntensity = crossMax - crossMin;
    float deringWeight = clamp(1.0 - edgeIntensity * 2.5, 0.0, 0.85);

    vec3 result = cM + vec3(diff * deringWeight);
    return vec4(clamp(result, 0.0, 1.0), c.a);
}

// Pass 3: Anime Line Art Contrast & Detail Reconstruction
//!HOOK MAIN
//!BIND DERINGTEX
//!SAVE LINETEX
//!DESC Anime Line Art Contrast Restoration & Thinning

vec4 hook() {
    vec4 c = DERINGTEX_tex(DERINGTEX_pos);
    vec2 pt = DERINGTEX_pt;
    vec3 luma_w = vec3(0.2627, 0.6780, 0.0593);

    float lNW = dot(DERINGTEX_tex(DERINGTEX_pos + vec2(-pt.x, -pt.y)).rgb, luma_w);
    float lN  = dot(DERINGTEX_tex(DERINGTEX_pos + vec2(0.0,   -pt.y)).rgb, luma_w);
    float lNE = dot(DERINGTEX_tex(DERINGTEX_pos + vec2( pt.x, -pt.y)).rgb, luma_w);
    float lW  = dot(DERINGTEX_tex(DERINGTEX_pos + vec2(-pt.x, 0.0)).rgb, luma_w);
    float lM  = dot(c.rgb, luma_w);
    float lE  = dot(DERINGTEX_tex(DERINGTEX_pos + vec2( pt.x, 0.0)).rgb, luma_w);
    float lSW = dot(DERINGTEX_tex(DERINGTEX_pos + vec2(-pt.x,  pt.y)).rgb, luma_w);
    float lS  = dot(DERINGTEX_tex(DERINGTEX_pos + vec2(0.0,    pt.y)).rgb, luma_w);
    float lSE = dot(DERINGTEX_tex(DERINGTEX_pos + vec2( pt.x,  pt.y)).rgb, luma_w);

    float gx = (-lNW + lNE - 2.0 * lW + 2.0 * lE - lSW + lSE);
    float gy = (-lNW - 2.0 * lN - lNE + lSW + 2.0 * lS + lSE);
    float grad = sqrt(gx * gx + gy * gy);

    float avgNeighbor = (lNW + lN + lNE + lW + lE + lSW + lS + lSE) * 0.125;
    float lineProfile = max(0.0, avgNeighbor - lM);

    // Counter chroma 4:2:0 subsampling blur by slightly enhancing line density
    float lineFactor = clamp(grad * 1.8 * lineProfile * 4.0, 0.0, 0.20);
    vec3 result = c.rgb * (1.0 - lineFactor);

    return vec4(clamp(result, 0.0, 1.0), c.a);
}

// AMD FidelityFX Super Resolution v1.0.2 (EASU + RCAS)

// Pass 4: Edge-Adaptive Spatial Upsampling (Reconstruction)
//!HOOK MAIN
//!BIND LINETEX
//!SAVE EASUTEX
//!DESC AMD FidelityFX FSR 1.0 (EASU Edge-Adaptive Reconstruction)
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h

#define FSR_EASU_DIR_THRESHOLD 0.25
#define FSR_EASU_DERING 1

vec4 hook() {
    vec2 pp = LINETEX_pos * LINETEX_size - vec2(0.5);
    vec2 fp = floor(pp);
    pp -= fp;

    vec4 f = LINETEX_tex(vec2((fp + vec2(0.5, 0.5)) * LINETEX_pt));
    vec4 g = LINETEX_tex(vec2((fp + vec2(1.5, 0.5)) * LINETEX_pt));
    vec4 j = LINETEX_tex(vec2((fp + vec2(0.5, 1.5)) * LINETEX_pt));
    vec4 k = LINETEX_tex(vec2((fp + vec2(1.5, 1.5)) * LINETEX_pt));

    // Directional edge estimation
    vec3 lum = vec3(0.2627, 0.6780, 0.0593);
    float lf = dot(f.rgb, lum);
    float lg = dot(g.rgb, lum);
    float lj = dot(j.rgb, lum);
    float lk = dot(k.rgb, lum);

    float dirX = (lg - lf) + (lk - lj);
    float dirY = (lj - lf) + (lk - lg);
    float edgeStrength = abs(dirX) + abs(dirY);

    vec4 top = mix(f, g, pp.x);
    vec4 bot = mix(j, k, pp.x);
    vec4 mid = mix(top, bot, pp.y);

    if (edgeStrength > FSR_EASU_DIR_THRESHOLD) {
        float dirLen = max(length(vec2(dirX, dirY)), 0.0001);
        vec2 dirNorm = vec2(dirX, dirY) / dirLen;
        vec4 edgeSample1 = LINETEX_tex(LINETEX_pos + dirNorm * LINETEX_pt * 0.5);
        vec4 edgeSample2 = LINETEX_tex(LINETEX_pos - dirNorm * LINETEX_pt * 0.5);
        mid = mix(mid, (edgeSample1 + edgeSample2) * 0.5, 0.45);
    }

#if (FSR_EASU_DERING == 1)
    vec4 min_val = min(min(f, g), min(j, k));
    vec4 max_val = max(max(f, g), max(j, k));
    mid = clamp(mid, min_val, max_val);
#endif

    return mid;
}

// Pass 2: Robust Contrast Adaptive Sharpening (RCAS)
//!HOOK MAIN
//!BIND EASUTEX
//!SAVE RCASTEX
//!DESC AMD FidelityFX FSR 1.0 (RCAS Sharpening)
//!WIDTH EASUTEX.w
//!HEIGHT EASUTEX.h

#define SHARPNESS 3.00
#define FSR_RCAS_DENOISE 0.70
#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0))

float APrxMedRcpF1(float a) {
    float b = uintBitsToFloat(uint(0x7ef19fff) - floatBitsToUint(max(a, 0.00001)));
    return b * (-b * a + 2.0);
}

vec4 hook() {
    vec4 b_rgba = EASUTEX_texOff(vec2(0.0, -1.0));
    vec4 d_rgba = EASUTEX_texOff(vec2(-1.0, 0.0));
    vec4 e_rgba = EASUTEX_tex(EASUTEX_pos);
    vec4 f_rgba = EASUTEX_texOff(vec2(1.0, 0.0));
    vec4 h_rgba = EASUTEX_texOff(vec2(0.0, 1.0));

    vec3 lum = vec3(0.2627, 0.6780, 0.0593);
    float b = dot(b_rgba.rgb, lum);
    float d = dot(d_rgba.rgb, lum);
    float e = dot(e_rgba.rgb, lum);
    float f = dot(f_rgba.rgb, lum);
    float h = dot(h_rgba.rgb, lum);

    float mn = min(min(min(b, d), f), min(h, e));
    float mx = max(max(max(b, d), f), max(h, e));

    vec2 peakC = vec2(1.0, -4.0);
    float hitMin = min(mn, e) / (4.0 * mx + 0.00001);
    float hitMax = (peakC.x - max(mx, e)) / (4.0 * mn + peakC.y);
    float lobe = max(-hitMin, hitMax);
    lobe = max(float(-FSR_RCAS_LIMIT), min(lobe, 0.0)) * (SHARPNESS * 1.5);
    // Stability: keep 1 + 4*lobe > 0 (RCAS denominator) so extreme sharpness
    // saturates at the strongest stable sharpening instead of diverging.
    lobe = max(lobe, -0.24);

    // Denoise attenuation
    float contrast = mx - mn;
    float denoiseAtten = clamp(contrast / max(FSR_RCAS_DENOISE, 0.001), 0.0, 1.0);
    lobe *= denoiseAtten;

    float rcpL = APrxMedRcpF1(4.0 * lobe + 1.0);
    vec3 result = (lobe * b_rgba.rgb + lobe * d_rgba.rgb + lobe * h_rgba.rgb + lobe * f_rgba.rgb + e_rgba.rgb) * rcpL;
    return vec4(clamp(result, 0.0, 1.0), e_rgba.a);
}

// AMD FidelityFX Contrast Adaptive Sharpening (CAS) — POST-upscale (1440p):
// afila la imagen ya reescalada por FSR sin amplificar los escalones
// (dientes de sierra) del source 720p que ocurriria con CAS pre-upscale.
//!HOOK MAIN
//!BIND RCASTEX
//!SAVE CASTEX
//!DESC FidelityFX Contrast Adaptive Sharpening (CAS, post-FSR)

#define SHARPNESS 0.70

vec4 hook() {
    vec4 e = RCASTEX_tex(RCASTEX_pos);
    vec4 b = RCASTEX_texOff(vec2(0.0, -1.0));
    vec4 d = RCASTEX_texOff(vec2(-1.0, 0.0));
    vec4 f = RCASTEX_texOff(vec2(1.0, 0.0));
    vec4 h = RCASTEX_texOff(vec2(0.0, 1.0));

    // RGB to luma (Rec. 709 / Rec. 2020 perceptual weights)
    vec3 luma_w = vec3(0.2627, 0.6780, 0.0593);
    float b_l = dot(b.rgb, luma_w);
    float d_l = dot(d.rgb, luma_w);
    float e_l = dot(e.rgb, luma_w);
    float f_l = dot(f.rgb, luma_w);
    float h_l = dot(h.rgb, luma_w);

    // Min and max luma in cross neighborhood
    float mn = min(min(min(b_l, d_l), min(f_l, h_l)), e_l);
    float mx = max(max(max(b_l, d_l), max(f_l, h_l)), e_l);

    // Smooth reciprocal with responsive sharpness weighting
    float amp = clamp(min(mn, 1.0 - mx) / max(mx - mn, 0.0001), 0.0, 0.25);
    float w = -sqrt(amp) * (SHARPNESS * 0.45);

    // Filter RGB
    vec3 col = (b.rgb + d.rgb + f.rgb + h.rgb) * w + e.rgb;
    col = clamp(col / (4.0 * w + 1.0), 0.0, 1.0);

    return vec4(col, e.a);
}

// FXAA final (FXAA v2 de Lottes, port de mattdesl/glsl-fxaa) — anti-aliasing
// AL FINAL DE TODO: suaviza los escalones residuales de diagonales (dientes
// de sierra) en el grid final tras CAS/RCAS. Sin texture2DLod ni bit-ops.
//!HOOK MAIN
//!BIND CASTEX
//!DESC FXAA final (anti-aliasing al final de la cadena)

#define FXAA_REDUCE_MIN (1.0 / 128.0)
#define FXAA_REDUCE_MUL (1.0 / 8.0)
#define FXAA_SPAN_MAX 8.0

vec4 hook() {
    vec4 texColor = CASTEX_tex(CASTEX_pos);
    vec2 inverseVP = CASTEX_pt;
    vec2 v_rgbNW = CASTEX_pos + vec2(-inverseVP.x, -inverseVP.y);
    vec2 v_rgbNE = CASTEX_pos + vec2( inverseVP.x, -inverseVP.y);
    vec2 v_rgbSW = CASTEX_pos + vec2(-inverseVP.x,  inverseVP.y);
    vec2 v_rgbSE = CASTEX_pos + vec2( inverseVP.x,  inverseVP.y);

    vec3 rgbNW = CASTEX_tex(v_rgbNW).xyz;
    vec3 rgbNE = CASTEX_tex(v_rgbNE).xyz;
    vec3 rgbSW = CASTEX_tex(v_rgbSW).xyz;
    vec3 rgbSE = CASTEX_tex(v_rgbSE).xyz;
    vec3 rgbM = texColor.xyz;
    vec3 luma = vec3(0.299, 0.587, 0.114);
    float lumaNW = dot(rgbNW, luma);
    float lumaNE = dot(rgbNE, luma);
    float lumaSW = dot(rgbSW, luma);
    float lumaSE = dot(rgbSE, luma);
    float lumaM = dot(rgbM, luma);
    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));

    vec2 dir;
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));

    float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2(FXAA_SPAN_MAX, FXAA_SPAN_MAX), max(vec2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), dir * rcpDirMin)) * inverseVP;

    vec3 rgbA = 0.5 * (
        CASTEX_tex(CASTEX_pos + dir * (1.0 / 3.0 - 0.5)).xyz +
        CASTEX_tex(CASTEX_pos + dir * (2.0 / 3.0 - 0.5)).xyz);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (
        CASTEX_tex(CASTEX_pos + dir * -0.5).xyz +
        CASTEX_tex(CASTEX_pos + dir * 0.5).xyz);

    float lumaB = dot(rgbB, luma);
    if ((lumaB < lumaMin) || (lumaB > lumaMax))
        return vec4(rgbA, texColor.a);
    else
        return vec4(rgbB, texColor.a);
}
