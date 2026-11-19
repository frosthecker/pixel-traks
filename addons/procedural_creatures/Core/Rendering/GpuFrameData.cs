// Procedural Pixel Creatures - GPU renderer, per-frame CPU packed data.
//
// The heavy per-pixel work (SDF evaluation, soft union, z resolve, toon stylization, contours,
// outline) runs in two canvas_item shaders. This class is the plain C# (engine free) transfer
// buffer between the CPU pose preparation and the two GPU passes. CreatureRenderer fills it; the
// runtime uploads the arrays as small data textures.
//
// Layout notes
//  - Primitives are packed in group order so the pixel shader can group them by a single value.
//  - Every texel is rgba, uploaded as RGBA half (the native float texture format on GLES3 class
//    hardware). Half is exact for all integer style channels used here.
//  - Tiles: each group of TileSize x TileSize canvas pixels stores the ascending list of primitive
//    indices whose bounds touch it (a counting sort built here on the CPU). The pixel shader walks
//    that short list instead of testing every primitive of the model for every pixel, which is what
//    makes the shader fast enough for low end GPUs.

using System;

namespace PixelCreatures.Core.Rendering
{
    public sealed class GpuFrameData
    {
        /// <summary>Texels per primitive row (see the layout in CreatureRenderer.Gpu.cs).</summary>
        public const int PrimTexels = 23;
        /// <summary>Number of baked facet directions per primitive.</summary>
        public const int FacetDirs = 7;
        /// <summary>Texels per group row.</summary>
        public const int GroupTexels = 2;

        /// <summary>Edge of one candidate binning tile in canvas pixels.</summary>
        public const int TileSize = 8;
        /// <summary>Candidate texels per texture row.</summary>
        public const int CandTexelsPerRow = 8;
        /// <summary>Candidates per texture row (two packed per texel).</summary>
        public const int CandPerRow = CandTexelsPerRow * 2;

        /// <summary>Texels per feature row: origin x/y, centre, tile row.</summary>
        public const int FeatureTexels = 4;
        /// <summary>Edge of one baked eye tile in pixels.</summary>
        public const int EyeTile = 24;
        public const int MaxFeatures = 24;

        public int Width, Height, OriginX, OriginY;

        public int PrimCount;
        public int GroupCount;
        public int FeatureCount;
        /// <summary>Canvas pixel rectangle that contains every visible feature (empty when none).</summary>
        public int FeatureX0 = 1, FeatureY0 = 1, FeatureX1 = 0, FeatureY1 = 0;

        /// <summary>Primitive data, PrimCount * PrimTexels texels of 4 floats.</summary>
        public float[] PrimRows = Array.Empty<float>();
        /// <summary>Group data, GroupCount * GroupTexels texels of 4 floats.</summary>
        public float[] GroupRows = Array.Empty<float>();
        /// <summary>Feature data, MaxFeatures * FeatureTexels texels of 4 floats.</summary>
        public float[] FeatureRows = new float[MaxFeatures * FeatureTexels * 4];
        /// <summary>Baked eye tiles, one EyeTile * EyeTile R8 tile per feature slot.</summary>
        public byte[] EyeTiles = new byte[EyeTile * EyeTile * MaxFeatures];
        /// <summary>Baked ground shadow mask (255 = shadow), canvas sized.</summary>
        public byte[] ShadowMask = Array.Empty<byte>();
        public bool ShadowMaskUsed;
        /// <summary>Canvas rectangle the shadow mask currently holds valid values for (empty when none).</summary>
        public int ShadowX0 = 1, ShadowY0 = 1, ShadowX1, ShadowY1;
        /// <summary>Canvas size the mask rectangle was recorded for.</summary>
        public int ShadowW = -1, ShadowH = -1;

        /// <summary>Packed index -> source primitive index.</summary>
        public int[] SourceOrder = Array.Empty<int>();

        /// <summary>Coarse spatial index over the primitives: one texel per TileSize tile (start, count).</summary>
        public int TileCols, TileRows;
        public float[] TileRanges = Array.Empty<float>();
        /// <summary>Candidate primitive indices, two per texel (x and z).</summary>
        public float[] Candidates = Array.Empty<float>();
        public int CandidateTexels;

        public bool HasContent;
        public int ContentX0, ContentY0, ContentX1, ContentY1;

        /// <summary>Rows of the creature-to-view rotation (facet directions are baked in creature space).</summary>
        public readonly float[] ViewRows = new float[9];
        public readonly float[] LightView = new float[3];
        public readonly float[] HalfView = new float[3];
        public readonly float[] LateralView = new float[3];
        public float PatternScale;

        public bool Overflow;
        public int OverflowLeft, OverflowRight, OverflowTop, OverflowBottom;

        public void Prepare(int w, int h, int originX, int originY, int prims, int groups)
        {
            Width = w; Height = h; OriginX = originX; OriginY = originY;
            if (PrimRows.Length < prims * PrimTexels * 4) PrimRows = new float[prims * PrimTexels * 4];
            if (SourceOrder.Length < prims) SourceOrder = new int[prims];
            if (GroupRows.Length < groups * GroupTexels * 4) GroupRows = new float[groups * GroupTexels * 4];
            if (ShadowMask.Length < w * h) ShadowMask = new byte[w * h];
            TileCols = (w + TileSize - 1) / TileSize;
            TileRows = (h + TileSize - 1) / TileSize;
            if (TileRanges.Length != TileCols * TileRows * 4)
                TileRanges = new float[TileCols * TileRows * 4];
            PrimCount = 0;
            GroupCount = groups;
            FeatureCount = 0;
            FeatureX0 = w; FeatureY0 = h; FeatureX1 = -1; FeatureY1 = -1;
            CandidateTexels = 0;
            HasContent = false;
            ContentX0 = w; ContentY0 = h; ContentX1 = -1; ContentY1 = -1;
            Overflow = false;
            OverflowLeft = OverflowRight = OverflowTop = OverflowBottom = 0;
            ShadowMaskUsed = false;
            if (ShadowW != w || ShadowH != h)
            {
                // A different canvas invalidates the recorded shadow rectangle: the mask bytes that the
                // old rectangle covered would otherwise be sampled as a phantom shadow.
                ShadowW = w; ShadowH = h;
                ShadowX0 = 1; ShadowY0 = 1; ShadowX1 = 0; ShadowY1 = 0;
                Array.Clear(ShadowMask, 0, Math.Min(ShadowMask.Length, w * h));
            }
            Array.Clear(FeatureRows, 0, FeatureRows.Length);
        }
    }

    /// <summary>
    /// Engine free result of the one time per model bake: the surface atlas (patterns, micro texture,
    /// scutes resolved to per texel material/shade/lighting data) plus the style and palette tables.
    /// </summary>
    public sealed class GpuModelBuild
    {
        public int PrimCount;
        /// <summary>Atlas rectangle per primitive: x, y, width, height in atlas texels.</summary>
        public int[] TileRects = Array.Empty<int>();
        /// <summary>RGBA8 atlas: R = material slot, G = shade bias + 16, B = lighting offset, A = seam.</summary>
        public byte[] Atlas = Array.Empty<byte>();
        public int AtlasW, AtlasH;
        /// <summary>16 slots x 2 rows of 4 floats: (wrap, light, base, shadow), (specular, texture, faceted, 0).</summary>
        public float[] Style = new float[16 * 2 * 4];
        /// <summary>Palette indices as a 16 x 8 texture: x = material slot, y = shade (row major).</summary>
        public byte[] Ramp = new byte[16 * 8];
        /// <summary>Per source primitive: 7 facet directions in creature space (3 floats each).</summary>
        public float[] FacetDirs = Array.Empty<float>();
        public long BakeTicks;
    }
}
