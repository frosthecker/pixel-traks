// Procedural Pixel Creatures - renderer selection.

namespace PixelCreatures.Runtime
{
    /// <summary>Chooses between the GPU shader pipeline and the original CPU rasterizer.</summary>
    public enum RendererMode
    {
        /// <summary>GPU when the display can run the shaders (not headless / software rasterized).</summary>
        Auto,
        /// <summary>Always use the two pass GPU renderer (fails over to the CPU path if it cannot start).</summary>
        Gpu,
        /// <summary>Always use the original CPU rasterizer (also used for creatures in water).</summary>
        Cpu,
    }
}
