using UnityEngine;

namespace DarkWarFog
{
    /// <summary>
    /// Lighthouse / unit vision probe. Place empty GameObjects in the scene to test FOW clearing.
    /// </summary>
    public class FogVisionSource : MonoBehaviour
    {
        [Tooltip("World-space vision radius in meters.")]
        public float radius = 15f;

        [Tooltip("Soft edge width as a fraction of radius (0..1).")]
        [Range(0f, 1f)]
        public float softEdge = 0.35f;

        [Tooltip("When disabled, this source is ignored.")]
        public bool contribute = true;

        void OnDrawGizmosSelected()
        {
            Gizmos.color = new Color(0.2f, 0.8f, 1f, 0.35f);
            Gizmos.DrawWireSphere(transform.position, radius);
        }
    }
}
