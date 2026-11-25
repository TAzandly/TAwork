using UnityEngine;

namespace DarkWarFog
{
    /// <summary>
    /// Clears each FogOverlaySlice mask and stamps all FogVisionSource lighthouses into UV space.
    /// </summary>
    public class FogOverlayUpdater : MonoBehaviour
    {
        public FogOverlaySlice[] slices;
        public FogVisionSource[] sources;
        public bool autoFindOnAwake = true;
        public bool updateEveryFrame = true;
        public Color clearColor = Color.black;

        [Header("Stamp")]
        public Shader stampShader;
        public float minRadiusUV = 0.01f;

        Material _stampMat;

        void Awake()
        {
            if (autoFindOnAwake)
            {
                if (slices == null || slices.Length == 0)
                    slices = FindObjectsOfType<FogOverlaySlice>();
                if (sources == null || sources.Length == 0)
                    sources = FindObjectsOfType<FogVisionSource>();
            }

            if (stampShader == null)
                stampShader = Shader.Find("Hidden/DarkWarFog/FogVisionStamp");
            if (stampShader != null)
                _stampMat = new Material(stampShader);
        }

        void OnDestroy()
        {
            if (_stampMat != null)
                Destroy(_stampMat);
        }

        void LateUpdate()
        {
            if (updateEveryFrame)
                RebuildMasks();
        }

        [ContextMenu("Rebuild Masks Now")]
        public void RebuildMasks()
        {
            if (_stampMat == null)
            {
                if (stampShader == null)
                    stampShader = Shader.Find("Hidden/DarkWarFog/FogVisionStamp");
                if (stampShader != null)
                    _stampMat = new Material(stampShader);
            }
            if (_stampMat == null)
                return;

            if (autoFindOnAwake)
            {
                slices = FindObjectsOfType<FogOverlaySlice>();
                sources = FindObjectsOfType<FogVisionSource>();
            }
            if (slices == null)
                return;

            for (int s = 0; s < slices.Length; s++)
            {
                var slice = slices[s];
                if (slice == null || !slice.isActiveAndEnabled)
                    continue;

                slice.EnsureRT();
                slice.ClearMask(clearColor);

                Vector4 channelMask = ChannelMask(slice.channelMode);

                if (sources != null)
                {
                    for (int i = 0; i < sources.Length; i++)
                    {
                        var src = sources[i];
                        if (src == null || !src.isActiveAndEnabled || !src.contribute)
                            continue;

                        // Stamp only on sheets that cover this world point (UV in range).
                        if (!slice.WorldToMaskUV(src.transform.position, out Vector2 uv))
                            continue;

                        float radiusUV = Mathf.Max(minRadiusUV, slice.WorldRadiusToMaskUV(src.radius));
                        _stampMat.SetVector("_CenterUV", new Vector4(uv.x, uv.y, 0f, 0f));
                        _stampMat.SetFloat("_RadiusUV", radiusUV);
                        _stampMat.SetFloat("_SoftEdge", src.softEdge);
                        _stampMat.SetVector("_ChannelMask", channelMask);
                        Graphics.Blit(null, slice.MaskRT, _stampMat);
                    }
                }

                slice.BindMaskToMaterial();
            }
        }

        static Vector4 ChannelMask(FogOverlaySlice.VisionChannelMode mode)
        {
            switch (mode)
            {
                case FogOverlaySlice.VisionChannelMode.Green:
                    return new Vector4(0f, 1f, 0f, 1f);
                case FogOverlaySlice.VisionChannelMode.Red:
                    return new Vector4(1f, 0f, 0f, 1f);
                default:
                    return new Vector4(1f, 1f, 1f, 1f);
            }
        }
    }
}
