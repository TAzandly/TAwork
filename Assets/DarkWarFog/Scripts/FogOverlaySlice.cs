using UnityEngine;

namespace DarkWarFog
{
    /// <summary>
    /// One war-fog overlay sheet (e.g. EID 3149 / 3154). Owns a mask RT sampled in mesh UV space.
    /// </summary>
    [RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
    public class FogOverlaySlice : MonoBehaviour
    {
        public enum VisionChannelMode
        {
            /// <summary>Write R=G=B (works for both 3149 Mas→G and 3154 Mas→R).</summary>
            RGBSame = 0,
            /// <summary>3149-style: drive G.</summary>
            Green = 1,
            /// <summary>3154-style: drive R.</summary>
            Red = 2
        }

        [Header("Mask RT")]
        public int resolution = 256;
        public VisionChannelMode channelMode = VisionChannelMode.RGBSame;

        [Header("Debug")]
        public bool drawBoundsGizmo = true;
        public bool drawMappedSourceGizmo = true;

        MeshRenderer _renderer;
        MeshFilter _filter;
        RenderTexture _maskRT;
        MaterialPropertyBlock _block;
        Bounds _localMeshBounds;
        bool _hasMeshBounds;
        bool _hasUvMap;

        // local XZ → mesh UV: u = ax + bz + c, v = dx + ez + f
        float _a, _b, _c, _d, _e, _f;
        float _uvPerMeter;

        public RenderTexture MaskRT => _maskRT;
        public Renderer TargetRenderer => _renderer;

        void Awake()
        {
            Cache();
            EnsureRT();
            BindMaskToMaterial();
        }

        void OnDestroy()
        {
            if (_maskRT != null)
            {
                _maskRT.Release();
                Destroy(_maskRT);
                _maskRT = null;
            }
        }

        void Cache()
        {
            _renderer = GetComponent<MeshRenderer>();
            _filter = GetComponent<MeshFilter>();
            _block = new MaterialPropertyBlock();
            _hasUvMap = false;

            var mesh = _filter != null ? _filter.sharedMesh : null;
            if (mesh == null)
                return;

            _localMeshBounds = mesh.bounds;
            _hasMeshBounds = true;
            BuildAffineUvMap(mesh);
        }

        void BuildAffineUvMap(Mesh mesh)
        {
            var verts = mesh.vertices;
            var uvs = mesh.uv;
            if (verts == null || uvs == null || verts.Length < 3 || uvs.Length != verts.Length)
                return;

            // Least-squares fit: [x z 1] * [a b c]^T = u  (and same for v).
            // Normal equations over unique samples.
            double sxx = 0, sxz = 0, sx1 = 0, szz = 0, sz1 = 0, s11 = 0;
            double sxu = 0, szu = 0, s1u = 0, sxv = 0, szv = 0, s1v = 0;
            int n = verts.Length;
            for (int i = 0; i < n; i++)
            {
                double x = verts[i].x;
                double z = verts[i].z;
                double u = uvs[i].x;
                double v = uvs[i].y;
                sxx += x * x; sxz += x * z; sx1 += x;
                szz += z * z; sz1 += z; s11 += 1.0;
                sxu += x * u; szu += z * u; s1u += u;
                sxv += x * v; szv += z * v; s1v += v;
            }

            if (!Solve3x3(sxx, sxz, sx1, sxz, szz, sz1, sx1, sz1, s11, sxu, szu, s1u, out _a, out _b, out _c))
                return;
            if (!Solve3x3(sxx, sxz, sx1, sxz, szz, sz1, sx1, sz1, s11, sxv, szv, s1v, out _d, out _e, out _f))
                return;

            _hasUvMap = true;

            // UV change per local meter (for radius conversion).
            float gu = Mathf.Sqrt(_a * _a + _b * _b);
            float gv = Mathf.Sqrt(_d * _d + _e * _e);
            _uvPerMeter = Mathf.Max(gu, gv);

            // Verify residual on a few verts (debug only).
            float maxErr = 0f;
            for (int i = 0; i < n; i += Mathf.Max(1, n / 16))
            {
                Vector2 pred = LocalXzToUv(verts[i].x, verts[i].z);
                maxErr = Mathf.Max(maxErr, Vector2.Distance(pred, uvs[i]));
            }
            if (maxErr > 0.05f)
                Debug.LogWarning(name + " FogOverlaySlice UV fit residual=" + maxErr.ToString("0.###") +
                                 " (mesh UV may be non-planar)");
        }

        static bool Solve3x3(
            double a00, double a01, double a02,
            double a10, double a11, double a12,
            double a20, double a21, double a22,
            double b0, double b1, double b2,
            out float x0, out float x1, out float x2)
        {
            x0 = x1 = x2 = 0f;
            double det =
                a00 * (a11 * a22 - a12 * a21) -
                a01 * (a10 * a22 - a12 * a20) +
                a02 * (a10 * a21 - a11 * a20);
            if (System.Math.Abs(det) < 1e-12)
                return false;

            double inv = 1.0 / det;
            double c00 = (a11 * a22 - a12 * a21) * inv;
            double c01 = (a02 * a21 - a01 * a22) * inv;
            double c02 = (a01 * a12 - a02 * a11) * inv;
            double c10 = (a12 * a20 - a10 * a22) * inv;
            double c11 = (a00 * a22 - a02 * a20) * inv;
            double c12 = (a02 * a10 - a00 * a12) * inv;
            double c20 = (a10 * a21 - a11 * a20) * inv;
            double c21 = (a01 * a20 - a00 * a21) * inv;
            double c22 = (a00 * a11 - a01 * a10) * inv;

            x0 = (float)(c00 * b0 + c01 * b1 + c02 * b2);
            x1 = (float)(c10 * b0 + c11 * b1 + c12 * b2);
            x2 = (float)(c20 * b0 + c21 * b1 + c22 * b2);
            return true;
        }

        Vector2 LocalXzToUv(float x, float z)
        {
            return new Vector2(_a * x + _b * z + _c, _d * x + _e * z + _f);
        }

        public void EnsureRT()
        {
            if (_maskRT != null && (_maskRT.width != resolution || _maskRT.height != resolution))
            {
                _maskRT.Release();
                Destroy(_maskRT);
                _maskRT = null;
            }

            if (_maskRT == null)
            {
                _maskRT = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.ARGB32)
                {
                    name = name + "_FogMask",
                    filterMode = FilterMode.Bilinear,
                    wrapMode = TextureWrapMode.Clamp,
                    useMipMap = true,
                    autoGenerateMips = true
                };
                _maskRT.Create();
                ClearMask(Color.black);
            }
        }

        public void ClearMask(Color color)
        {
            EnsureRT();
            var prev = RenderTexture.active;
            RenderTexture.active = _maskRT;
            GL.Clear(true, true, color);
            RenderTexture.active = prev;
        }

        public void BindMaskToMaterial()
        {
            if (_renderer == null)
                Cache();
            if (_renderer == null || _maskRT == null)
                return;

            _renderer.GetPropertyBlock(_block);
            _block.SetTexture("_NoiseMap", _maskRT);
            _renderer.SetPropertyBlock(_block);
        }

        /// <summary>
        /// Map a world-space point into this sheet's mask UV using a fit from mesh verts↔UV.
        /// Returns false if the point is far outside the sheet's UV atlas rect.
        /// </summary>
        public bool WorldToMaskUV(Vector3 worldPos, out Vector2 maskUV)
        {
            maskUV = default;
            if (!_hasUvMap)
                Cache();
            if (!_hasUvMap)
                return false;

            Vector3 local = transform.InverseTransformPoint(worldPos);
            maskUV = LocalXzToUv(local.x, local.z);

            // Allow a little bleed so edge sources still stamp.
            const float pad = 0.05f;
            if (maskUV.x < -pad || maskUV.x > 1f + pad || maskUV.y < -pad || maskUV.y > 1f + pad)
                return false;
            return true;
        }

        /// <summary>
        /// Convert a world-space radius (meters) to mask UV radius on this sheet.
        /// </summary>
        public float WorldRadiusToMaskUV(float worldRadius)
        {
            if (!_hasUvMap)
                Cache();
            if (!_hasUvMap || worldRadius <= 0f)
                return 0f;

            // lossyScale stretches local meters → world meters; UV fit is in local space.
            float scaleXZ = Mathf.Max(Mathf.Abs(transform.lossyScale.x), Mathf.Abs(transform.lossyScale.z));
            float localRadius = worldRadius / Mathf.Max(scaleXZ, 1e-4f);
            return localRadius * Mathf.Max(_uvPerMeter, 1e-6f);
        }

        void OnDrawGizmos()
        {
            if (!drawBoundsGizmo)
                return;
            var mf = _filter != null ? _filter : GetComponent<MeshFilter>();
            if (mf == null || mf.sharedMesh == null)
                return;
            Gizmos.color = new Color(1f, 0.6f, 0.1f, 0.25f);
            Gizmos.matrix = transform.localToWorldMatrix;
            Bounds b = mf.sharedMesh.bounds;
            Gizmos.DrawWireCube(b.center, b.size);
        }

        void OnDrawGizmosSelected()
        {
            if (!drawMappedSourceGizmo || !_hasUvMap)
                return;

            // Visualize where each FogVisionSource lands on this sheet (world projection of UV).
            var sources = FindObjectsOfType<FogVisionSource>();
            Gizmos.color = Color.cyan;
            for (int i = 0; i < sources.Length; i++)
            {
                var src = sources[i];
                if (src == null || !src.contribute) continue;
                if (!WorldToMaskUV(src.transform.position, out Vector2 uv))
                    continue;

                // Approximate: draw a disc in world using inverse of radius mapping.
                float r = src.radius;
                Gizmos.DrawWireSphere(src.transform.position, r);
                Gizmos.DrawLine(src.transform.position, src.transform.position + Vector3.up * 2f);
            }
        }
    }
}
