Shader "DarkWarFog/Overlay"
{
    Properties
    {
        [Header(Maps)]
        _NoiseMap ("Noise Mask t0", 2D) = "white" {}
        _FogMap ("Fog Color Map t1", 2D) = "white" {}
        _ClearMask ("Clear Mask Screen t2 optional", 2D) = "black" {}
        [Toggle(_USE_CLEAR_MASK)] _UseClearMask ("Use Clear Mask", Float) = 0

        [Header(Mask Mix)]
        _MasR ("Mix Toward G", Range(0, 1)) = 1
        _MasG ("Mix Toward B", Range(0, 1)) = 0
        _MasB ("Mix Toward A", Range(0, 1)) = 0

        [Header(Fog Color)]
        _FogAoColor ("Fog AO Dark Color", Color) = (0.023, 0.046, 0.069, 1)
        _FogColor ("Fog Tint Color", Color) = (0.58, 0.60, 0.57, 1)
        _FogColorBlend ("Tint Blend", Range(0, 1)) = 1
        _AlphaAdd ("Alpha Add From Soft", Range(0, 1)) = 1

        [Header(Scroll UV)]
        _ScrollSpeed ("Noise Scroll Speed XY", Vector) = (0.03, 0, 0, 0)
        _ScrollTime ("Scroll Time Override neg uses Time.y", Float) = -1
        _EdgeFade ("UV Edge Fade Width", Float) = 0.01

        [Header(Soft Particle)]
        _SoftFactor ("Depth Soft Factor", Float) = 0.42
        _DepthMipBias ("Depth Sample Mip Bias", Float) = 0

        [Header(Color Grade)]
        _Intensity ("Intensity", Float) = 1
        _Saturation ("Saturation", Float) = 1
        _ContrastA ("Contrast A", Float) = 1.02
        _ContrastB ("Contrast B", Float) = 0.8
        _ContrastBlend ("Contrast Blend", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off
            ZWrite Off
            ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0
            #pragma shader_feature_local _USE_CLEAR_MASK

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D(_NoiseMap);   SAMPLER(sampler_NoiseMap);
            TEXTURE2D(_FogMap);     SAMPLER(sampler_FogMap);
            TEXTURE2D(_ClearMask);  SAMPLER(sampler_ClearMask);

            CBUFFER_START(UnityPerMaterial)
                float4 _NoiseMap_ST;
                float4 _FogMap_ST;
                float4 _ClearMask_ST;
                half4 _FogAoColor;
                half4 _FogColor;
                half _FogColorBlend;
                half _AlphaAdd;
                half _MasR;
                half _MasG;
                half _MasB;
                float4 _ScrollSpeed;
                float _ScrollTime;
                float _EdgeFade;
                float _SoftFactor;
                float _DepthMipBias;
                half _Intensity;
                half _Saturation;
                half _ContrastA;
                half _ContrastB;
                half _ContrastBlend;
                half _UseClearMask;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv0 : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 screenPos : TEXCOORD0;
                // xy = FogMap (t1) UV: meshUV * FogMap_ST + scroll (capture vsout._output1.xy)
                // zw unused / reserved
                float4 fogUV : TEXCOORD1;
                float2 meshUV : TEXCOORD2; // FogMask (t0) uses raw mesh UV (capture Loc2)
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float4 positionCS = TransformWorldToHClip(positionWS);
                output.positionCS = positionCS;
                output.screenPos = ComputeScreenPos(positionCS);

                float t = _ScrollTime >= 0.0 ? _ScrollTime : _Time.y;
                float2 scroll = frac(float2(t, t) * _ScrollSpeed.xy);

                // Capture: t1 FogMap is tiled + scrolled; t0 mask is raw mesh UV.
                float2 fogMapUV = input.uv0 * _FogMap_ST.xy + _FogMap_ST.zw + scroll;
                output.fogUV = float4(fogMapUV, 0.0, 0.0);
                output.meshUV = input.uv0;
                return output;
            }

            half ChannelMixInverted(half4 tex)
            {
                half4 inv = 1.0h - tex;
                half m = inv.r;
                m = lerp(m, inv.g, _MasR);
                m = lerp(m, inv.b, _MasG);
                m = lerp(m, inv.a, _MasB);
                return m;
            }

            half3 GradeColor(half3 c)
            {
                c *= _Intensity;
                half lum = dot(c, half3(0.2125h, 0.7154h, 0.0721h));
                c = lum + _Saturation * (c - lum);
                half contrast = lerp(_ContrastA, _ContrastB, _ContrastBlend);
                c = (c - 0.5h) * contrast + 0.5h;
                return c;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                half mask = ChannelMixInverted(SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, input.meshUV));

                // Tint: soft expand around fog color, then square, then lerp from AO color.
                half3 tintFactor = (_FogColor.rgb - 1.0h) * 0.2h + 1.0h;
                half3 tinted = tintFactor * (_FogColor.rgb * _FogColor.rgb);
                half4 baseCol = half4(tinted, 1.0h);
                baseCol = lerp(_FogAoColor, baseCol, _FogColorBlend);

                half4 fogTex = SAMPLE_TEXTURE2D(_FogMap, sampler_FogMap, input.fogUV.xy);
                half softA = 1.0h - fogTex.a * baseCol.a;
                half4 rgbPremul = baseCol * fogTex;
                half alphaCombine = _AlphaAdd * softA + rgbPremul.a;
                half coverage = mask * alphaCombine;

                // Soft particle vs scene depth.
                float2 screenUV = input.screenPos.xy / max(input.screenPos.w, 1e-6);
                #if UNITY_REVERSED_Z
                    float rawDepth = SampleSceneDepth(screenUV);
                #else
                    float rawDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1.0, SampleSceneDepth(screenUV));
                #endif
                float sceneEyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);
                float particleEyeDepth = input.screenPos.w;
                half depthFade = saturate((sceneEyeDepth - particleEyeDepth) * _SoftFactor);
                coverage *= depthFade;
                coverage = saturate(coverage);

                #if defined(_USE_CLEAR_MASK)
                    half clear = SAMPLE_TEXTURE2D(_ClearMask, sampler_ClearMask, screenUV).r;
                    coverage *= (1.0h - clear);
                #endif

                // UV edge fade (quad border soft).
                float2 edgeUV = min(input.meshUV, 1.0 - input.meshUV);
                half edge = saturate(min(edgeUV.x, edgeUV.y) / max(_EdgeFade, 1e-5));
                half alpha = coverage * edge;

                half3 rgb = GradeColor(rgbPremul.rgb);
                return half4(rgb, alpha);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
