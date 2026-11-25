Shader "DarkWarFog/Terrain"
{
    // Restored from RDC EID 2005 (ground splat + war-fog lightmap + screen decal).
    // VS: ControlUV = (1 - UV0) * ST; Splat0/1 apply TRANSFORM_TEX twice; Splat2/3 once; LightMap = UV1 * ST.
    // PS: albedo = Splat1*G*L2 + Splat0*R*L1 + Splat2*B*L3 + Splat3*A*L4;
    //     lit = albedo * (LightColor * NdotL + SH); color = lerp(AO, lit, smoothstep(saturate(LM.r * 4.59)));
    //     optional screen-space decal glow (t0) attenuated by world Y and day time.
    Properties
    {
        [Header(Splat)]
        _Control ("Control t2", 2D) = "black" {}
        _Splat0 ("Splat 0 t3 (R)", 2D) = "white" {}
        _Splat1 ("Splat 1 t4 (G)", 2D) = "white" {}
        _Splat2 ("Splat 2 t5 (B)", 2D) = "white" {}
        _Splat3 ("Splat 3 t6 (A)", 2D) = "white" {}
        _Layer1Color ("Layer 1 Color", Color) = (1, 1, 1, 1)
        _Layer2Color ("Layer 2 Color", Color) = (1, 1, 1, 1)
        _Layer3Color ("Layer 3 Color", Color) = (1, 1, 1, 1)
        _Layer4Color ("Layer 4 Color", Color) = (1, 1, 1, 1)

        [Header(War Fog)]
        _LightMap ("Light Map t1", 2D) = "white" {}
        _LightMapMipBias ("Mip Bias", Float) = 0
        _LightMapAoColor ("Fog AO Color", Color) = (0, 0, 0, 1)
        _LightMapAoColor0 ("Fog AO Color Day", Color) = (0, 0, 0, 1)
        _GlobalDayTime ("Global Day Time", Range(0, 1)) = 0

        [Header(Decal)]
        [Toggle(_CUSTOM_DECAL)] _UseCustomDecal ("Use Custom Decal", Float) = 1
        _CustomDecalTexture ("Custom Decal t0", 2D) = "black" {}
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0
            #pragma shader_feature_local _CUSTOM_DECAL

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_Control);            SAMPLER(sampler_Control);
            TEXTURE2D(_Splat0);             SAMPLER(sampler_Splat0);
            TEXTURE2D(_Splat1);             SAMPLER(sampler_Splat1);
            TEXTURE2D(_Splat2);             SAMPLER(sampler_Splat2);
            TEXTURE2D(_Splat3);             SAMPLER(sampler_Splat3);
            TEXTURE2D(_LightMap);           SAMPLER(sampler_LightMap);
            TEXTURE2D(_CustomDecalTexture); SAMPLER(sampler_CustomDecalTexture);

            CBUFFER_START(UnityPerMaterial)
                float4 _Control_ST;
                float4 _Splat0_ST;
                float4 _Splat1_ST;
                float4 _Splat2_ST;
                float4 _Splat3_ST;
                float4 _LightMap_ST;
                float4 _CustomDecalTexture_ST;
                half4 _Layer1Color;
                half4 _Layer2Color;
                half4 _Layer3Color;
                half4 _Layer4Color;
                half4 _LightMapAoColor;
                half4 _LightMapAoColor0;
                half _GlobalDayTime;
                float _LightMapMipBias;
                half _UseCustomDecal;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv0 : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 uvControlAndLight : TEXCOORD0; // xy control, zw lightmap
                float4 uvSplat01 : TEXCOORD1;         // xy splat0, zw splat1
                float4 uvSplat23 : TEXCOORD2;         // xy splat2, zw splat3
                float3 positionWS : TEXCOORD3;
                float4 screenPos : TEXCOORD4;
                half4 shAndNdotL : TEXCOORD5;         // rgb SH, a NdotL
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float4 positionCS = TransformWorldToHClip(positionWS);

                output.positionCS = positionCS;
                output.positionWS = positionWS;
                output.screenPos = ComputeScreenPos(positionCS);

                // Capture: Control = (1 - UV0) * ST + offset
                output.uvControlAndLight.xy = (1.0 - input.uv0) * _Control_ST.xy + _Control_ST.zw;
                // LightMap uses UV1
                output.uvControlAndLight.zw = input.uv1 * _LightMap_ST.xy + _LightMap_ST.zw;

                // Capture VS applies TRANSFORM_TEX twice for Splat0 and Splat1
                float2 uvSplat0 = input.uv0 * _Splat0_ST.xy + _Splat0_ST.zw;
                output.uvSplat01.xy = uvSplat0 * _Splat0_ST.xy + _Splat0_ST.zw;
                float2 uvSplat1 = input.uv0 * _Splat1_ST.xy + _Splat1_ST.zw;
                output.uvSplat01.zw = uvSplat1 * _Splat1_ST.xy + _Splat1_ST.zw;

                output.uvSplat23.xy = input.uv0 * _Splat2_ST.xy + _Splat2_ST.zw;
                output.uvSplat23.zw = input.uv0 * _Splat3_ST.xy + _Splat3_ST.zw;

                Light mainLight = GetMainLight();
                half ndotl = saturate(dot(normalWS, mainLight.direction));
                half3 sh = SampleSH(normalWS);
                output.shAndNdotL = half4(sh, ndotl);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float bias = _LightMapMipBias;

                half4 control = SAMPLE_TEXTURE2D_BIAS(_Control, sampler_Control, input.uvControlAndLight.xy, bias);
                half3 splat0 = SAMPLE_TEXTURE2D_BIAS(_Splat0, sampler_Splat0, input.uvSplat01.xy, bias).rgb;
                half3 splat1 = SAMPLE_TEXTURE2D_BIAS(_Splat1, sampler_Splat1, input.uvSplat01.zw, bias).rgb;
                half3 splat2 = SAMPLE_TEXTURE2D_BIAS(_Splat2, sampler_Splat2, input.uvSplat23.xy, bias).rgb;
                half3 splat3 = SAMPLE_TEXTURE2D_BIAS(_Splat3, sampler_Splat3, input.uvSplat23.zw, bias).rgb;

                // Capture order: G*splat1 first, then R*splat0, B*splat2, A*splat3
                half3 albedo = splat1 * control.g * _Layer2Color.rgb;
                albedo = splat0 * control.r * _Layer1Color.rgb + albedo;
                albedo = splat2 * control.b * _Layer3Color.rgb + albedo;
                albedo = splat3 * control.a * _Layer4Color.rgb + albedo;

                Light mainLight = GetMainLight();
                half3 lighting = mainLight.color * input.shAndNdotL.w + input.shAndNdotL.xyz;
                half3 lit = albedo * lighting;

                half3 aoColor = lerp(_LightMapAoColor.rgb, _LightMapAoColor0.rgb, _GlobalDayTime);
                half lightMapR = SAMPLE_TEXTURE2D_BIAS(_LightMap, sampler_LightMap, input.uvControlAndLight.zw, bias).r;
                half visibility = saturate(lightMapR * 4.59h);
                visibility = smoothstep(0.0h, 1.0h, visibility);

                half3 color = lerp(aoColor, lit, visibility);

                #if defined(_CUSTOM_DECAL)
                    float2 decalUV = input.screenPos.xy / max(input.screenPos.w, 1e-6);
                    half4 decal = SAMPLE_TEXTURE2D(_CustomDecalTexture, sampler_CustomDecalTexture, decalUV);
                    half3 glow = decal.rgb * 20.0h;
                    half invHeight = 1.0h / max(decal.a * 500.0h, 1e-6h);
                    half heightFactor = saturate(input.positionWS.y * invHeight);
                    half atten = 1.0h - smoothstep(0.0h, 1.0h, heightFactor);
                    half dayT = saturate((1.0h - _GlobalDayTime) * 6.66666651h);
                    half dayFactor = 1.0h - smoothstep(0.0h, 1.0h, dayT);
                    color += color * glow * atten * dayFactor;
                #endif

                return half4(color, 1.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma target 3.0
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _Control_ST;
                float4 _Splat0_ST;
                float4 _Splat1_ST;
                float4 _Splat2_ST;
                float4 _Splat3_ST;
                float4 _LightMap_ST;
                float4 _CustomDecalTexture_ST;
                half4 _Layer1Color;
                half4 _Layer2Color;
                half4 _Layer3Color;
                half4 _Layer4Color;
                half4 _LightMapAoColor;
                half4 _LightMapAoColor0;
                half _GlobalDayTime;
                float _LightMapMipBias;
                half _UseCustomDecal;
            CBUFFER_END

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings ShadowVert(Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
            #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                output.positionCS = positionCS;
                return output;
            }

            half4 ShadowFrag(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _Control_ST;
                float4 _Splat0_ST;
                float4 _Splat1_ST;
                float4 _Splat2_ST;
                float4 _Splat3_ST;
                float4 _LightMap_ST;
                float4 _CustomDecalTexture_ST;
                half4 _Layer1Color;
                half4 _Layer2Color;
                half4 _Layer3Color;
                half4 _Layer4Color;
                half4 _LightMapAoColor;
                half4 _LightMapAoColor0;
                half _GlobalDayTime;
                float _LightMapMipBias;
                half _UseCustomDecal;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings DepthVert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half DepthFrag(Varyings input) : SV_TARGET
            {
                return input.positionCS.z;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
