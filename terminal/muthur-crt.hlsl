// MU/TH/UR 6000: shader CRT dla Windows Terminal (experimental.pixelShaderPath).
// Efekty: poświata luminoforu, linie skanowania, pas odświeżania, winieta,
// lekkie migotanie i szum. Bez zakrzywienia ekranu, żeby tekst był czytelny.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings {
    float  Time;        // sekundy od uruchomienia
    float  Scale;       // skala DPI
    float2 Resolution;  // rozmiar w pikselach
    float4 Background;  // kolor tła
};

#define GLOW_STRENGTH     0.55
#define GLOW_RADIUS       1.6
#define SCANLINE_STRENGTH 0.22
#define SCANLINE_PERIOD   3.0
#define VIGNETTE_STRENGTH 0.35
#define FLICKER_STRENGTH  0.012
#define BAND_STRENGTH     0.05
#define BAND_SPEED        0.12
#define NOISE_STRENGTH    0.025

float hash(float2 p) {
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float3 glow(float2 tex) {
    float2 px = GLOW_RADIUS * Scale / Resolution;
    float3 sum = float3(0, 0, 0);
    // 12 próbek na dwóch pierścieniach daje miękką poświatę wokół liter.
    [unroll] for (int i = 0; i < 6; i++) {
        float a = i * 1.0471976; // 60 stopni
        float2 dir = float2(cos(a), sin(a));
        sum += shaderTexture.Sample(samplerState, tex + dir * px).rgb;
        sum += shaderTexture.Sample(samplerState, tex + dir * px * 2.5).rgb * 0.6;
    }
    return sum / 9.6;
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET {
    float4 base = shaderTexture.Sample(samplerState, tex);
    float3 color = base.rgb;

    // Poświata: dodaje tylko jaśniejsze od tła piksele z sąsiedztwa.
    float3 halo = max(glow(tex) - Background.rgb, 0.0);
    color += halo * GLOW_STRENGTH;

    // Linie skanowania: co SCANLINE_PERIOD pikseli (z uwzględnieniem DPI).
    float scanPhase = pos.y / (SCANLINE_PERIOD * Scale);
    float scan = 0.5 + 0.5 * cos(scanPhase * 6.2831853);
    color *= 1.0 - SCANLINE_STRENGTH * scan;

    // Powolny jaśniejszy pas odświeżania przesuwający się w dół ekranu.
    float bandPos = frac(Time * BAND_SPEED);
    float band = exp(-pow((tex.y - bandPos) * 9.0, 2.0));
    color += band * BAND_STRENGTH * float3(0.55, 1.0, 0.65);

    // Winieta: przyciemnione rogi kineskopu.
    float2 c = tex - 0.5;
    float vig = 1.0 - VIGNETTE_STRENGTH * dot(c, c) * 2.2;
    color *= saturate(vig);

    // Migotanie zasilania i szum luminoforu.
    float flicker = 1.0 + FLICKER_STRENGTH * sin(Time * 61.0) * sin(Time * 7.3);
    color *= flicker;
    color += (hash(pos.xy + frac(Time) * 97.0) - 0.5) * NOISE_STRENGTH;

    return float4(saturate(color), base.a);
}
