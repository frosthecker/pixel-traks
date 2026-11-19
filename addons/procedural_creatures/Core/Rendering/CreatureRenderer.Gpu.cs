// Procedural Pixel Creatures - GPU renderer, CPU side preparation.
//
// Everything here runs on the CPU once per model (surface atlas) or once per animation frame (pose
// packing). The GPU does the per-pixel work; this file only produces the small data textures it
// consumes:
//
//   GpuModelBuild  surface patterns, micro texture and scutes baked into an RGBA8 atlas in the
//                  primitive's own (pose independent) surface coordinates, plus the material style
//                  table and the palette ramp. Baked once per model.
//   GpuFrameData   per pose: primitive parameters (13 texels each), group table, a per tile
//                  candidate index, feature list, baked eye tiles and the ground shadow mask.
//
// The helper functions (Sd2D, Front, Rim, SurfaceAt, ScuteOffset, TextureLightOffset, the eye
// stamp...) are shared with the CPU rasterizer, so the baked data matches what the CPU path
// would have computed for the same pixel.

using System;
using System.Collections.Generic;
using PixelCreatures.Core.Anatomy;
using PixelCreatures.Core.Palettes;

namespace PixelCreatures.Core.Rendering
{
    public sealed partial class CreatureRenderer
    {
        // ------------------------------------------------------------------ view setup

        /// <summary>Sets the rasterizer up for one view/pose without touching the frame buffers.</summary>
        private void SetUpView(in ViewSpec view, CreatureAnatomy anatomy, CreaturePose pose, ref RenderStats stats)
        {
            var wv = PixelCamera.WorldToView(view.Elevation);
            _creatureToView = wv * PixelCamera.YawRotation(view.Yaw);
            _offsetView = wv.Mul(view.RootOffset);
            _groundOffsetView = wv.Mul(new Vec3(view.RootOffset.X, 0, view.RootOffset.Z));
            _lightView = wv.Mul(PixelCamera.WorldLight).Normalized();
            _halfView = (_lightView + Vec3.UnitZ).Normalized();
            _lateralView = _creatureToView.Mul(Vec3.UnitZ);
            _forwardView = _creatureToView.Mul(Vec3.UnitX);
            _patternScale = anatomy.Metrics.PatternScale;
            PrepareBones(pose.Skeleton);
            PreparePrimitives(anatomy, view.Quality, ref stats);
        }

        // ------------------------------------------------------------------ per model bake

        /// <summary>
        /// Bakes everything that only depends on the model (not the pose): patterns, countershading,
        /// micro texture and scute seams sampled in surface space, plus the style and palette tables.
        /// </summary>
        public GpuModelBuild BuildGpuModel(CreatureAnatomy anatomy, CreaturePalette palette, SurfaceSpec surface,
            CreaturePose pose, in ViewSpec view)
        {
            var canvas = anatomy.Canvas;
            _w = canvas.Width;
            _h = canvas.Height;
            _ox = canvas.OriginX;
            _oy = canvas.OriginY;
            EnsureGpuBuffers(anatomy);
            var stats = new RenderStats();
            SetUpView(view, anatomy, pose, ref stats);

            var build = new GpuModelBuild { PrimCount = _ppCount };
            BuildStyleTable(surface, build);
            BuildRamp(palette, build);
            BakeFacetDirs(anatomy, build);
            BakeSurfaceAtlas(anatomy, surface, build);
            return build;
        }

        private static void BuildStyleTable(SurfaceSpec surface, GpuModelBuild build)
        {
            int last = (int)MaterialSlot.Count - 1;
            for (int s = 0; s < 16; s++)
            {
                var style = surface.StyleOf((MaterialSlot)Math.Min(s, last));
                int a = s * 4, b = 64 + s * 4;
                build.Style[a + 0] = (float)style.Wrap;
                build.Style[a + 1] = (float)style.LightThreshold;
                build.Style[a + 2] = (float)style.BaseThreshold;
                build.Style[a + 3] = (float)style.ShadowThreshold;
                build.Style[b + 0] = (float)style.SpecularThreshold;
                build.Style[b + 1] = (float)style.Texture;
                build.Style[b + 2] = style.Faceted ? 1f : 0f;
                build.Style[b + 3] = 0f;
            }
        }

        private static void BuildRamp(CreaturePalette palette, GpuModelBuild build)
        {
            int last = (int)MaterialSlot.Count - 1;
            for (int s = 0; s < 16; s++)
            {
                var slot = (MaterialSlot)Math.Min(s, last);
                for (int shade = 0; shade < 8; shade++) build.Ramp[shade * 16 + s] = palette.Index(slot, shade);
            }
        }

        /// <summary>
        /// Bakes the seven seeded facet directions of every source primitive in creature space. The pixel
        /// shader picks the one that best matches the smooth normal (and rotates it into view space), so
        /// chiselled materials keep the exact same faceting as the CPU rasterizer.
        /// </summary>
        private static void BakeFacetDirs(CreatureAnatomy anatomy, GpuModelBuild build)
        {
            int n = anatomy.Primitives.Count;
            build.FacetDirs = new float[n * GpuFrameData.FacetDirs * 3];
            for (int i = 0; i < n; i++)
            {
                var def = anatomy.Primitives[i];
                uint seed = def.FacetSeed == 0 ? (uint)(i * 2654435761u) : def.FacetSeed;
                for (int k = 0; k < GpuFrameData.FacetDirs; k++)
                {
                    double a = StableHash.Hash01(seed, k, 1) * DMath.TwoPi;
                    double e = StableHash.Hash01(seed, k, 2) * 1.2 - 0.2;
                    DMath.SinCos(a, out double sa, out double ca);
                    DMath.SinCos(e, out double se, out double ce);
                    int o = (i * GpuFrameData.FacetDirs + k) * 3;
                    build.FacetDirs[o + 0] = (float)(ca * ce);
                    build.FacetDirs[o + 1] = (float)se;
                    build.FacetDirs[o + 2] = (float)(sa * ce);
                }
            }
        }

        /// <summary>Tile size in atlas texels for one primitive's surface parametrization.</summary>
        private static void SurfaceTileSize(ref PPrim p, out int tw, out int th)
        {
            const int min = 2, max = 64;
            if (p.Domain == PatternDomain.None) { tw = 1; th = 1; return; }
            double len = Math.Max(1.0, p.DomainLength);
            switch (p.Kind)
            {
                case PrimKind.Ellipsoid:
                {
                    double du = Math.Abs(p.U1 - p.U0) * len;
                    double dv = 2.0 * Math.PI * p.REq;
                    tw = (int)Math.Clamp(Math.Ceiling(du), min, max);
                    th = (int)Math.Clamp(Math.Ceiling(dv), min, max);
                    break;
                }
                case PrimKind.RoundCone:
                {
                    double du = Math.Abs(p.U1 - p.U0) * len;
                    double dv = 2.0 * Math.PI * Math.Max(p.Ra, p.Rb);
                    tw = (int)Math.Clamp(Math.Ceiling(du), min, max);
                    th = (int)Math.Clamp(Math.Ceiling(dv), min, max);
                    break;
                }
                default:
                    tw = (int)Math.Clamp(Math.Ceiling(len), min, max);
                    th = tw;
                    break;
            }
        }

        private void BakeSurfaceAtlas(CreatureAnatomy anatomy, SurfaceSpec surface, GpuModelBuild build)
        {
            int n = _ppCount;
            // tile rects are indexed by *source* primitive (primitives that failed preparation are
            // skipped, so the prepared index is not the source index)
            int sources = anatomy.Primitives.Count;
            build.TileRects = new int[sources * 4];
            int[] tw = new int[n], th = new int[n];
            for (int i = 0; i < n; i++) SurfaceTileSize(ref _pp[i], out tw[i], out th[i]);

            // shelf packing
            const int atlasW = 1024;
            int x = 0, y = 0, shelf = 0;
            for (int i = 0; i < n; i++)
            {
                if (x + tw[i] > atlasW) { x = 0; y += shelf; shelf = 0; }
                int tr = _pp[i].Source * 4;
                build.TileRects[tr + 0] = x;
                build.TileRects[tr + 1] = y;
                build.TileRects[tr + 2] = tw[i];
                build.TileRects[tr + 3] = th[i];
                x += tw[i];
                shelf = Math.Max(shelf, th[i]);
            }
            int atlasH = Math.Max(1, y + shelf);
            build.AtlasW = atlasW;
            build.AtlasH = atlasH;
            build.Atlas = new byte[atlasW * atlasH * 4];

            for (int i = 0; i < n; i++) BakePrimTile(surface, build, i, tw[i], th[i]);
        }

        private void BakePrimTile(SurfaceSpec surface, GpuModelBuild build, int prim, int tw, int th)
        {
            ref var p = ref _pp[prim];
            int tr = p.Source * 4;
            int tx = build.TileRects[tr + 0], ty = build.TileRects[tr + 1];
            bool hasSurface = p.Domain != PatternDomain.None;
            bool scutes = (p.Flags & PrimFlags.Scutes) != 0 && p.Kind == PrimKind.Ellipsoid && hasSurface;
            bool noPattern = (p.Flags & PrimFlags.NoPattern) != 0;
            double len = Math.Max(1.0, p.DomainLength);

            for (int iy = 0; iy < th; iy++)
            {
                double sv = (iy + 0.5) / th;
                for (int ix = 0; ix < tw; ix++)
                {
                    double su = (ix + 0.5) / tw;
                    var sp = new SurfacePoint { Domain = p.Domain };
                    if (hasSurface)
                    {
                        switch (p.Kind)
                        {
                            case PrimKind.Ellipsoid:
                            {
                                double qx = 2.0 * su - 1.0;
                                double ring = Math.Sqrt(Math.Max(0.0, 1.0 - qx * qx));
                                double theta = (sv - 0.5) * 2.0 * Math.PI;
                                DMath.SinCos(theta, out double sin, out double cos);
                                double tn = DMath.Lerp(p.U0, p.U1, su);
                                sp.T = tn;
                                sp.U = tn * len;
                                sp.Theta = theta;
                                sp.V = theta * p.REq * Math.Max(0.35, ring);
                                sp.Local = new Vec3(qx, ring * cos, ring * sin);
                                sp.Side = sp.Local.Z >= 0 ? 1 : -1;
                                break;
                            }
                            case PrimKind.RoundCone:
                            {
                                double theta = (sv - 0.5) * 2.0 * Math.PI;
                                DMath.SinCos(theta, out double sin, out double cos);
                                double tn = DMath.Lerp(p.U0, p.U1, su);
                                double r = DMath.Lerp(p.Ra, p.Rb, su);
                                double inv = r / Math.Max(0.5, r);
                                sp.T = tn;
                                sp.U = tn * len;
                                sp.Theta = theta;
                                sp.V = theta * r;
                                sp.Local = new Vec3(su * 2.0 - 1.0, inv * cos, inv * sin);
                                sp.Side = cos * r >= 0 ? 1 : -1;
                                break;
                            }
                            default:
                            {
                                double t = su;
                                double d = (sv - 0.5) * 2.0;
                                double l1 = Math.Max(0.0, (t - d) * 0.5), l2 = Math.Max(0.0, (t + d) * 0.5);
                                sp.T = t;
                                sp.U = t * len;
                                sp.V = (l2 - l1) * len * 0.5;
                                sp.Local = new Vec3(l1, l2, 0);
                                sp.Side = 1;
                                sp.Plate = true;
                                break;
                            }
                        }
                    }

                    var slot = p.Material;
                    int bias = p.ShadeBias;
                    if (hasSurface && !noPattern)
                        slot = surface.Evaluate(sp, slot, ref bias, _patternScale);

                    double ndl = 0;
                    bool seam = false;
                    if (hasSurface)
                    {
                        var style = surface.StyleOf(slot);
                        if (slot == MaterialSlot.Hair)
                            ndl += TextureLightOffset(style.Texture, surface, sp, _patternScale, Math.Max(0.85, surface.TextureAmount));
                        else if (surface.TextureAmount > 0.05 &&
                                 (slot == MaterialSlot.Primary || slot == MaterialSlot.Secondary ||
                                  slot == MaterialSlot.Marking || slot == MaterialSlot.White))
                            ndl += TextureLightOffset(style.Texture, surface, sp, _patternScale);
                        if (scutes) ndl += ScuteOffset(ref p, sp, out seam);
                    }

                    int o = ((ty + iy) * build.AtlasW + (tx + ix)) * 4;
                    build.Atlas[o + 0] = (byte)slot;
                    build.Atlas[o + 1] = (byte)Math.Clamp(bias + 16, 0, 255);
                    build.Atlas[o + 2] = (byte)Math.Clamp(Math.Round((ndl + 0.75) / 1.5 * 255.0), 0, 255);
                    build.Atlas[o + 3] = seam ? (byte)255 : (byte)0;
                }
            }
        }

        // ------------------------------------------------------------------ per frame packing

        private int[] _tileBox = Array.Empty<int>();
        private int[] _tileCursor = Array.Empty<int>();

        /// <summary>Packs the current pose into the GPU transfer buffers.</summary>
        public void BuildGpuFrame(CreatureAnatomy anatomy, CreaturePalette palette, CreaturePose pose, in ViewSpec view,
            GpuModelBuild build, GpuFrameData data)
        {
            var canvas = anatomy.Canvas;
            data.Prepare(canvas.Width, canvas.Height, canvas.OriginX, canvas.OriginY, anatomy.Primitives.Count, anatomy.Groups.Count);
            _w = canvas.Width;
            _h = canvas.Height;
            _ox = canvas.OriginX;
            _oy = canvas.OriginY;
            EnsureGpuBuffers(anatomy);
            var stats = new RenderStats();
            SetUpView(view, anatomy, pose, ref stats);

            var m = _creatureToView;
            data.ViewRows[0] = (float)m.C0.X;
            data.ViewRows[1] = (float)m.C1.X;
            data.ViewRows[2] = (float)m.C2.X;
            data.ViewRows[3] = (float)m.C0.Y;
            data.ViewRows[4] = (float)m.C1.Y;
            data.ViewRows[5] = (float)m.C2.Y;
            data.ViewRows[6] = (float)m.C0.Z;
            data.ViewRows[7] = (float)m.C1.Z;
            data.ViewRows[8] = (float)m.C2.Z;
            data.LightView[0] = (float)_lightView.X;
            data.LightView[1] = (float)_lightView.Y;
            data.LightView[2] = (float)_lightView.Z;
            data.HalfView[0] = (float)_halfView.X;
            data.HalfView[1] = (float)_halfView.Y;
            data.HalfView[2] = (float)_halfView.Z;
            data.LateralView[0] = (float)_lateralView.X;
            data.LateralView[1] = (float)_lateralView.Y;
            data.LateralView[2] = (float)_lateralView.Z;
            data.PatternScale = (float)_patternScale;

            PackGpuPrimitives(anatomy, build, data);
            PackGpuTiles(data);
            PackGpuFeatures(anatomy, palette, pose, data);
            BakeGpuShadow(anatomy, pose, data);

            data.Overflow = stats.Overflow;
            data.OverflowLeft = stats.OverflowLeft;
            data.OverflowRight = stats.OverflowRight;
            data.OverflowTop = stats.OverflowTop;
            data.OverflowBottom = stats.OverflowBottom;

            int cx0 = _w, cy0 = _h, cx1 = -1, cy1 = -1;
            for (int i = 0; i < _ppCount; i++)
            {
                ref var p = ref _pp[i];
                int x0 = Math.Max(0, p.X0), y0 = Math.Max(0, p.Y0);
                int x1 = Math.Min(_w - 1, p.X1), y1 = Math.Min(_h - 1, p.Y1);
                if (x1 < x0 || y1 < y0) continue;
                if (x0 < cx0) cx0 = x0;
                if (y0 < cy0) cy0 = y0;
                if (x1 > cx1) cx1 = x1;
                if (y1 > cy1) cy1 = y1;
            }
            data.HasContent = cx1 >= cx0 && cy1 >= cy0;
            if (data.HasContent)
            {
                data.ContentX0 = Math.Max(0, cx0 - 1);
                data.ContentY0 = Math.Max(0, cy0 - 1);
                data.ContentX1 = Math.Min(_w - 1, cx1 + 1);
                data.ContentY1 = Math.Min(_h - 1, cy1 + 1);
            }
        }

        private static void SetTexel(float[] rows, int offset, float x, float y, float z, float w)
        {
            rows[offset + 0] = x;
            rows[offset + 1] = y;
            rows[offset + 2] = z;
            rows[offset + 3] = w;
        }

        /// <summary>
        /// Packs the prepared primitives. Row layout (one texel = 4 floats):
        ///   0 kind, group, material, flags        8/9/10 kind specific geometry
        ///   1 bbox x0,y0,x1,y1                   11/12/13 inverse ellipsoid transform
        ///   2 Cx,Cy,Cz,RMin                      14 side, shade bias
        ///   3 Qxx,Qxy,Qxz,Qyy                    15 atlas rect x,y,w,h
        ///   4 Qyz,Qzz,Mxx,Mxy                    16..22 seven facet directions
        ///   5 Myy,REq,DomainLength,hasSurface
        ///   6..10 kind specific geometry
        /// </summary>
        private void PackGpuPrimitives(CreatureAnatomy anatomy, GpuModelBuild build, GpuFrameData data)
        {
            int groups = anatomy.Groups.Count;
            data.GroupCount = groups;
            int[] tileRects = build.TileRects;
            int idx = 0;
            for (int g = 0; g < groups; g++)
            {
                int start = idx;
                int count = _groupCount[g];
                var grp = anatomy.Groups[g];
                SetTexel(data.GroupRows, (g * GpuFrameData.GroupTexels + 0) * 4,
                    start, count, (float)grp.BlendRadius, (float)grp.DepthBias);
                SetTexel(data.GroupRows, (g * GpuFrameData.GroupTexels + 1) * 4,
                    grp.Side, (int)grp.Flags, 0, 0);
                int pad = grp.BlendRadius > 0 ? (int)Math.Ceiling(grp.BlendRadius) : 0;

                for (int j = 0; j < count; j++)
                {
                    ref var p = ref _pp[_groupList[_groupStart[g] + j]];
                    int src = p.Source;
                    float[] r = data.PrimRows;
                    int b = idx * GpuFrameData.PrimTexels * 4;
                    SetTexel(r, b + 0 * 4, (int)p.Kind, g, (int)p.Material, (int)p.Flags);
                    SetTexel(r, b + 1 * 4, p.X0, p.Y0, p.X1, p.Y1);
                    SetTexel(r, b + 2 * 4, (float)p.Cx, (float)p.Cy, (float)p.Cz, (float)p.RMin);
                    SetTexel(r, b + 3 * 4, (float)p.Qxx, (float)p.Qxy, (float)p.Qxz, (float)p.Qyy);
                    SetTexel(r, b + 4 * 4, (float)p.Qyz, (float)p.Qzz, (float)p.Mxx, (float)p.Mxy);
                    SetTexel(r, b + 5 * 4, (float)p.Myy, (float)p.REq, (float)p.DomainLength,
                        p.Domain != PatternDomain.None ? 1 : 0);
                    switch (p.Kind)
                    {
                        case PrimKind.Ellipsoid:
                            // rows of AInv (the shader needs q = AInv * rel; AInv is not symmetric)
                            SetTexel(r, b + 6 * 4, (float)p.AInv.C0.X, (float)p.AInv.C1.X, (float)p.AInv.C2.X, 0);
                            SetTexel(r, b + 7 * 4, (float)p.AInv.C0.Y, (float)p.AInv.C1.Y, (float)p.AInv.C2.Y, 0);
                            SetTexel(r, b + 8 * 4, (float)p.AInv.C0.Z, (float)p.AInv.C1.Z, (float)p.AInv.C2.Z, 0);
                            break;
                        case PrimKind.RoundCone:
                            SetTexel(r, b + 6 * 4, (float)p.A.X, (float)p.A.Y, (float)p.A.Z, (float)p.Ra);
                            SetTexel(r, b + 7 * 4, (float)p.B.X, (float)p.B.Y, (float)p.B.Z, (float)p.Rb);
                            SetTexel(r, b + 8 * 4, (float)p.Dx, (float)p.Dy, (float)p.H2, (float)p.ZTop);
                            SetTexel(r, b + 9 * 4, (float)p.CoefA, (float)p.CoefB, p.Degenerate ? 1 : 0, 0);
                            SetTexel(r, b + 10 * 4, (float)p.Up.X, (float)p.Up.Y, (float)p.Up.Z, 0);
                            break;
                        default:
                            SetTexel(r, b + 6 * 4, (float)p.P0.X, (float)p.P0.Y, (float)p.P0.Z, 0);
                            SetTexel(r, b + 7 * 4, (float)p.P1.X, (float)p.P1.Y, (float)p.P1.Z, 0);
                            SetTexel(r, b + 8 * 4, (float)p.P2.X, (float)p.P2.Y, (float)p.P2.Z, 0);
                            SetTexel(r, b + 9 * 4, (float)p.N.X, (float)p.N.Y, (float)p.N.Z, (float)p.Area2);
                            SetTexel(r, b + 10 * 4, p.BackFace ? 1 : 0, 0, 0, 0);
                            break;
                    }
                    SetTexel(r, b + 14 * 4, (float)p.U0, (float)p.U1, p.Side, p.ShadeBias);
                    int tr = src * 4;
                    if (tileRects != null && tr + 3 < tileRects.Length)
                        SetTexel(r, b + 15 * 4, tileRects[tr], tileRects[tr + 1], tileRects[tr + 2], tileRects[tr + 3]);
                    else
                        SetTexel(r, b + 15 * 4, 0, 0, 1, 1);
                    int fo = src * GpuFrameData.FacetDirs * 3;
                    int fn = build.FacetDirs.Length;
                    for (int k = 0; k < GpuFrameData.FacetDirs; k++)
                    {
                        int o = fo + k * 3;
                        if (o + 2 < fn)
                            SetTexel(r, b + (16 + k) * 4, build.FacetDirs[o], build.FacetDirs[o + 1], build.FacetDirs[o + 2], 0);
                        else
                            SetTexel(r, b + (16 + k) * 4, 0, 1, 0, 0);
                    }
                    data.SourceOrder[idx] = src;

                    if ((idx + 1) * 5 > _tileBox.Length) Array.Resize(ref _tileBox, Math.Max(64, _tileBox.Length * 2));
                    _tileBox[idx * 5 + 0] = p.X0;
                    _tileBox[idx * 5 + 1] = p.Y0;
                    _tileBox[idx * 5 + 2] = p.X1;
                    _tileBox[idx * 5 + 3] = p.Y1;
                    _tileBox[idx * 5 + 4] = pad;
                    idx++;
                }
            }
            data.PrimCount = idx;
        }

        /// <summary>
        /// Buckets the packed primitives into TileSize x TileSize canvas tiles in ascending primitive
        /// index order (which is group order), so the pixel shader can skip primitives that cannot
        /// touch a pixel without reading their data. Counting sort: one pass counts, one scatters.
        /// </summary>
        private void PackGpuTiles(GpuFrameData data)
        {
            int cols = data.TileCols, rows = data.TileRows, tiles = cols * rows;
            if (tiles <= 0) return;
            if (_tileCursor.Length < tiles + 1) _tileCursor = new int[tiles + 1];
            var cursor = _tileCursor;
            Array.Clear(cursor, 0, tiles + 1);

            int prims = data.PrimCount;
            for (int i = 0; i < prims; i++)
            {
                TileRange(i, cols, rows, out int tx0, out int ty0, out int tx1, out int ty1);
                for (int ty = ty0; ty <= ty1; ty++)
                    for (int tx = tx0; tx <= tx1; tx++) cursor[ty * cols + tx + 1]++;
            }
            for (int t = 0; t < tiles; t++) cursor[t + 1] += cursor[t];
            int total = cursor[tiles];
            int texels = (total + 1) / 2;
            int rowsNeeded = (texels + GpuFrameData.CandTexelsPerRow - 1) / GpuFrameData.CandTexelsPerRow;
            int floats = rowsNeeded * GpuFrameData.CandTexelsPerRow * 4;
            if (data.Candidates.Length < floats) data.Candidates = new float[floats];
            else Array.Clear(data.Candidates, 0, floats);
            data.CandidateTexels = texels;

            var ranges = data.TileRanges;
            for (int t = 0; t < tiles; t++)
                SetTexel(ranges, t * 4, cursor[t], cursor[t + 1] - cursor[t], 0, 0);

            for (int t = 0; t < tiles; t++) cursor[t] = (int)ranges[t * 4];
            var cand = data.Candidates;
            for (int i = 0; i < prims; i++)
            {
                TileRange(i, cols, rows, out int tx0, out int ty0, out int tx1, out int ty1);
                for (int ty = ty0; ty <= ty1; ty++)
                {
                    int row = ty * cols;
                    for (int tx = tx0; tx <= tx1; tx++)
                    {
                        int slot = cursor[row + tx]++;
                        cand[(slot >> 1) * 4 + ((slot & 1) << 1)] = i;
                    }
                }
            }
        }

        private void TileRange(int prim, int cols, int rows, out int tx0, out int ty0, out int tx1, out int ty1)
        {
            const int T = GpuFrameData.TileSize;
            int b = prim * 5;
            int pad = _tileBox[b + 4];
            int x0 = _tileBox[b + 0] - pad, y0 = _tileBox[b + 1] - pad;
            int x1 = _tileBox[b + 2] + pad, y1 = _tileBox[b + 3] + pad;
            if (x1 < 0 || y1 < 0 || x0 >= _w || y0 >= _h) { tx0 = 1; tx1 = 0; ty0 = 1; ty1 = 0; return; }
            tx0 = Math.Max(0, x0 / T);
            ty0 = Math.Max(0, y0 / T);
            tx1 = Math.Min(cols - 1, x1 / T);
            ty1 = Math.Min(rows - 1, y1 / T);
        }

        private void PackGpuFeatures(CreatureAnatomy anatomy, CreaturePalette palette, CreaturePose pose, GpuFrameData data)
        {
            var expr = pose.Expression;
            int n = 0;
            for (int fi = 0; fi < anatomy.Features.Count && n < GpuFrameData.MaxFeatures; fi++)
            {
                var f = anatomy.Features[fi];
                var bv = _boneView[f.Bone];
                Vec3 pos = bv.Point(f.LocalPosition);
                if (!pos.IsFinite) continue;
                Vec3 nrm = bv.Dir(f.LocalNormal).NormalizedOr(Vec3.UnitZ);
                double sx = _ox + pos.X, sy = _oy - pos.Y;
                int cx = (int)Math.Floor(sx), cy = (int)Math.Floor(sy);
                bool inFrame = cx >= 0 && cy >= 0 && cx < _w && cy < _h;
                bool visible = inFrame && nrm.Z >= -0.12;
                int b = n * GpuFrameData.FeatureTexels * 4;
                float[] rows = data.FeatureRows;
                int tileHalf = GpuFrameData.EyeTile / 2;
                SetTexel(rows, b + 0 * 4, (float)(Math.Floor(sx) - tileHalf), (float)(Math.Floor(sy) - tileHalf), cx, cy);
                SetTexel(rows, b + 1 * 4, (float)pos.Z, (float)f.Size, (int)f.Kind, visible ? 1 : 0);
                SetTexel(rows, b + 2 * 4, n, (int)f.Material, nrm.Z > 0.15 ? 1 : 0, 0);
                SetTexel(rows, b + 3 * 4, (float)nrm.X, (float)nrm.Y, (float)nrm.Z, f.Brow > 0.4 ? 1 : 0);
                if (f.Kind == FeatureKind.Eye && visible)
                    BakeEyeTile(f, palette, expr, sx, sy, nrm, _boneScale[f.Bone], data.EyeTiles, n);
                if (visible)
                {
                    // the compose shader skips the feature loop outside this rectangle, which is
                    // most of the creature: features are small and only a few pixels wide
                    int r = f.Kind == FeatureKind.Eye ? tileHalf : 1;
                    data.FeatureX0 = Math.Min(data.FeatureX0, cx - r);
                    data.FeatureY0 = Math.Min(data.FeatureY0, cy - r);
                    data.FeatureX1 = Math.Max(data.FeatureX1, cx + r);
                    data.FeatureY1 = Math.Max(data.FeatureY1, cy + r);
                }
                n++;
            }
            data.FeatureCount = n;
        }

        /// <summary>
        /// Renders one eye into its own tile with the shared eye stamping logic (the same one the CPU
        /// path uses), so the GPU shows exactly the same eye pixels. Coverage and the depth test are
        /// applied in the compose shader, which is the only place that knows the frame buffer.
        /// </summary>
        private void BakeEyeTile(FeatureDef f, CreaturePalette palette, ExpressionState expr, double sx, double sy,
            Vec3 nrm, double scale, byte[] tiles, int tileRow)
        {
            int tw = GpuFrameData.EyeTile;
            int originX = (int)Math.Floor(sx) - tw / 2;
            int originY = (int)Math.Floor(sy) - tw / 2;
            int baseIdx = tileRow * tw * tw;
            // Only the tile of an eye that is baked this frame has to be reset: the compose shader reads
            // a tile only while its slot holds an eye, so stale pixels in other slots are never sampled.
            Array.Clear(tiles, baseIdx, tw * tw);
            void PutTile(int x, int y, byte c)
            {
                int tx = x - originX, ty = y - originY;
                if ((uint)tx >= (uint)tw || (uint)ty >= (uint)tw) return;
                tiles[baseIdx + ty * tw + tx] = c;
            }
            StampEye(f, palette, PutTile, sx, sy, nrm, expr, scale, null);
        }

        // Ellipse data of the blobs of the frame being baked: centre, inverse radii, weight.
        private float[] _blobParams = Array.Empty<float>();
        /// <summary>
        /// Bakes the soft ground shadow into a byte mask. The field is only evaluated inside the union of
        /// the blob ellipses (a few hundred pixels), never over the whole canvas.
        /// </summary>
        private void BakeGpuShadow(CreatureAnatomy anatomy, CreaturePose pose, GpuFrameData data)
        {
            data.ShadowMaskUsed = false;
            if (!Options.CastShadow) return;
            int n = _w * _h;
            if (_shadowField.Length < n) _shadowField = new float[n];
            BuildShadowBlobs(anatomy, pose);
            int blobs = _shadowBlobs.Count;
            if (blobs == 0) return;
            if (_blobParams.Length < blobs * 5) _blobParams = new float[blobs * 5];
            // Single precision on purpose: this runs per animation frame over a small ellipse, and
            // the Pi's FPU does doubles at half rate.
            float sinE = (float)DMath.Sin(PixelCamera.DefaultElevation);
            int x0 = _w, y0 = _h, x1 = -1, y1 = -1;
            for (int i = 0; i < blobs; i++)
            {
                var (bx, bz, br, bw) = _shadowBlobs[i];
                Vec3 c = _creatureToView.Mul(new Vec3(bx, 0, bz)) + _groundOffsetView;
                float rx = (float)br * 1.35f, ry = Math.Max(1f, (float)br * 1.35f * sinE);
                int b = i * 5;
                _blobParams[b + 0] = (float)(_ox + c.X);
                _blobParams[b + 1] = (float)(_oy - c.Y);
                _blobParams[b + 2] = 1f / (rx * rx);
                _blobParams[b + 3] = 1f / (ry * ry);
                _blobParams[b + 4] = (float)bw;
                int bx0 = Math.Max(0, (int)Math.Floor(_blobParams[b + 0] - rx));
                int bx1 = Math.Min(_w - 1, (int)Math.Ceiling(_blobParams[b + 0] + rx));
                int by0 = Math.Max(0, (int)Math.Floor(_blobParams[b + 1] - ry));
                int by1 = Math.Min(_h - 1, (int)Math.Ceiling(_blobParams[b + 1] + ry));
                if (bx1 < bx0 || by1 < by0) continue;
                if (bx0 < x0) x0 = bx0;
                if (by0 < y0) y0 = by0;
                if (bx1 > x1) x1 = bx1;
                if (by1 > y1) y1 = by1;
            }
            if (x1 < x0 || y1 < y0) return;
            // Both the field and the mask must be rewritten where the previous bake left values behind.
            int px0 = Math.Clamp(data.ShadowX0, 0, _w - 1), py0 = Math.Clamp(data.ShadowY0, 0, _h - 1);
            int px1 = Math.Clamp(data.ShadowX1, -1, _w - 1), py1 = Math.Clamp(data.ShadowY1, -1, _h - 1);
            int cx0 = Math.Min(x0, px0), cy0 = Math.Min(y0, py0);
            int cx1 = Math.Max(x1, px1), cy1 = Math.Max(y1, py1);
            for (int y = cy0; y <= cy1; y++)
            {
                int row = y * _w;
                Array.Clear(_shadowField, row + cx0, cx1 - cx0 + 1);
            }
            for (int i = 0; i < blobs; i++)
            {
                int b = i * 5;
                float scx = _blobParams[b + 0], scy = _blobParams[b + 1];
                float invRx2 = _blobParams[b + 2], invRy2 = _blobParams[b + 3];
                float wgt = _blobParams[b + 4];
                float rx = 1f / MathF.Sqrt(invRx2), ry = 1f / MathF.Sqrt(invRy2);
                int bx0 = Math.Max(x0, (int)Math.Floor(scx - rx)), bx1 = Math.Min(x1, (int)Math.Ceiling(scx + rx));
                int by0 = Math.Max(y0, (int)Math.Floor(scy - ry)), by1 = Math.Min(y1, (int)Math.Ceiling(scy + ry));
                for (int y = by0; y <= by1; y++)
                {
                    float dy = y + 0.5f - scy;
                    float dy2 = dy * dy * invRy2;
                    int row = y * _w;
                    for (int x = bx0; x <= bx1; x++)
                    {
                        float dx = x + 0.5f - scx;
                        float d2 = dx * dx * invRx2 + dy2;
                        if (d2 >= 1f) continue;
                        float f = 1f - d2;
                        _shadowField[row + x] += f * f * wgt;
                    }
                }
            }
            bool any = false;
            for (int y = cy0; y <= cy1; y++)
            {
                int row = y * _w;
                for (int x = cx0; x <= cx1; x++)
                {
                    int i = row + x;
                    if (_shadowField[i] > 0.33f) { data.ShadowMask[i] = 255; any = true; }
                    else data.ShadowMask[i] = 0;
                }
            }
            data.ShadowX0 = cx0; data.ShadowY0 = cy0; data.ShadowX1 = cx1; data.ShadowY1 = cy1;
            data.ShadowMaskUsed = any;
        }
    }
}
