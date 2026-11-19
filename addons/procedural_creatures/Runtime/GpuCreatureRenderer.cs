// Procedural Pixel Creatures - GPU textures and per actor GPU pipeline.
//
// GpuCreatureRenderer owns two SubViewports per creature:
//   pass 1  the G-buffer (depth, group, material slot, shade) written by creature_pixel.gdshader,
//   pass 2  the compose pass (outlines, contours, palette lookup) written by creature_compose.gdshader
//           into a plain RGBA texture.
// The pose is re-rendered at the animation frame rate only, so the per display frame cost of a creature
// is a single plain textured quad: the expensive shaders never run every frame (which matters a lot on
// low end GPUs such as the Raspberry Pi 4). The CPU only packs the small transfer buffers (see
// CreatureRenderer.Gpu.cs) and uploads them.
//
// Everything here is main thread only: textures, viewports and materials are engine objects. The
// packing itself runs on the render worker threads.

using System;
using System.Collections.Generic;
using Godot;
using PixelCreatures.Core;
using PixelCreatures.Core.Anatomy;
using PixelCreatures.Core.Palettes;
using PixelCreatures.Core.Rendering;

namespace PixelCreatures.Runtime
{
    internal static class GpuTextures
    {
        /// <summary>Converts floats to little endian half bytes (RGBAH upload buffers are reusable).</summary>
        public static byte[] ToHalfBytes(float[] src, int floats, byte[] dst)
        {
            for (int i = 0; i < floats; i++)
            {
                ushort h = BitConverter.HalfToUInt16Bits((Half)src[i]);
                dst[i * 2] = (byte)h;
                dst[i * 2 + 1] = (byte)(h >> 8);
            }
            return dst;
        }

        /// <summary>Creates (or recreates) a texture with the given size and a scratch buffer of matching size.</summary>
        public static ImageTexture Ensure(ref Image? image, ref ImageTexture? texture, ref byte[] buffer,
            int width, int height, Image.Format format, int channels)
        {
            width = Math.Max(1, width);
            height = Math.Max(1, height);
            int bytes = width * height * channels;
            if (buffer.Length != bytes) buffer = new byte[bytes];
            if (image == null || texture == null || image.GetWidth() != width || image.GetHeight() != height
                || image.GetFormat() != format)
            {
                image?.Dispose();
                texture?.Dispose();
                image = Image.CreateEmpty(width, height, false, format);
                texture = ImageTexture.CreateFromImage(image);
            }
            return texture;
        }

        public static void Upload(Image? image, ImageTexture? texture, byte[] buffer, int width, int height,
            Image.Format format)
        {
            if (image == null || texture == null) return;
            image.SetData(width, height, false, format, buffer);
            texture.Update(image);
        }
    }

    /// <summary>Global pool of reusable SubViewports to avoid per-creature allocation overhead.</summary>
/// Only the G-buffer viewport and ColorRect are pooled. Compose viewport/quad are per-creature
/// because the compose ShaderMaterial has per-creature parameters (color_table, lut_tex).
internal static class GpuViewportPool
{
    private static readonly Queue<SubViewport> _gbufferPool = new();
    private static readonly Queue<ColorRect> _rectPool = new();

    public static SubViewport RentGbuffer(out ColorRect rect)
    {
        if (_gbufferPool.Count > 0)
        {
            var vp = _gbufferPool.Dequeue();
            rect = _rectPool.Dequeue();
            rect.Size = new Vector2(1, 1);
            vp.Size = new Vector2I(1, 1);
            return vp;
        }
        rect = new ColorRect { Color = new Color(1, 1, 1, 1), MouseFilter = Control.MouseFilterEnum.Ignore };
        var vp2 = new SubViewport
        {
            RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled,
            TransparentBg = true,
            // The G-buffer is packed into normalized RGBA8 values, so it does not need HDR 2D
            // (which the Pi's V3D compatibility driver does not support anyway).
            UseHdr2D = false,
            GuiDisableInput = true,
            Size = new Vector2I(1, 1),
        };
        return vp2;
    }

    public static (SubViewport viewport, Sprite2D quad) RentCompose()
    {
        var quad = new Sprite2D
        {
            Centered = false,
            Position = Vector2.Zero,
            TextureFilter = CanvasItem.TextureFilterEnum.Nearest,
        };
        var vp = new SubViewport
        {
            RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled,
            TransparentBg = true,
            UseHdr2D = false,
            GuiDisableInput = true,
            Size = new Vector2I(1, 1),
        };
        return (vp, quad);
    }

    public static void ReturnGbuffer(SubViewport vp, ColorRect rect, Node owner)
    {
        if (vp == null || !GodotObject.IsInstanceValid(vp)) return;
        vp.RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled;
        rect.Material = null; // the per creature material is disposed with its renderer
        vp.RemoveChild(rect);
        owner.RemoveChild(vp);
        _gbufferPool.Enqueue(vp);
        _rectPool.Enqueue(rect);
    }

    public static void ReturnCompose(SubViewport vp, Sprite2D quad, Node owner)
    {
        if (vp == null || !GodotObject.IsInstanceValid(vp)) return;
        vp.RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled;
        vp.RemoveChild(quad);
        owner.RemoveChild(vp);
        vp.QueueFree();
        quad.QueueFree();
    }

    public static void Clear()
    {
        foreach (var vp in _gbufferPool) { if (GodotObject.IsInstanceValid(vp)) vp.QueueFree(); }
        foreach (var r in _rectPool) { if (GodotObject.IsInstanceValid(r)) r.QueueFree(); }
        _gbufferPool.Clear(); _rectPool.Clear();
    }
}

internal sealed class GpuCreatureRenderer : IDisposable
    {
        public const string PixelShaderPath = "res://addons/procedural_creatures/Runtime/Shaders/creature_pixel.gdshader";
        public const string ComposeShaderPath = "res://addons/procedural_creatures/Runtime/Shaders/creature_compose.gdshader";

        /// <summary>True when the engine can run the two shader passes (no headless / software raster).</summary>
        public static bool IsSupported
        {
            get
            {
                if (_supported.HasValue) return _supported.Value;
                bool ok = true;
                try
                {
                    string driver = DisplayServer.GetName();
                    if (driver == "headless") ok = false;
                    if (ok)
                    {
                        string adapter = RenderingServer.GetVideoAdapterName().ToLowerInvariant();
                        if (adapter.Contains("llvmpipe") || adapter.Contains("softpipe") ||
                            adapter.Contains("swrast") || adapter.Contains("software"))
                            ok = false;
                    }
                }
                catch { ok = false; }
                _supported = ok;
                return ok;
            }
        }
        private static bool? _supported;

        public readonly GpuFrameData Frame = new();
        public GpuModelBuild? Build { get; private set; }
        public string LastError { get; private set; } = string.Empty;
        public int Width { get; private set; } = 1;
        public int Height { get; private set; } = 1;
        public int OriginX { get; private set; }
        public int OriginY { get; private set; }

        private readonly CreatureActor _actor;
        private readonly Sprite2D _sprite;
        private readonly SubViewport _viewport;
        private readonly ColorRect _rect;
        private readonly SubViewport _outViewport;
        private readonly Sprite2D _outQuad;
        private readonly ShaderMaterial _pixel;
        private readonly ShaderMaterial _compose;
        private readonly CanvasItemMaterial _premult;
        private bool _composePending;

        private Image? _primImg, _groupImg, _tileImg, _candImg, _featureImg, _eyeImg, _shadowImg, _atlasImg, _styleImg, _rampImg, _lutImg;
        private ImageTexture? _primTex, _groupTex, _tileTex, _candTex, _featureTex, _eyeTex, _shadowTex, _atlasTex, _styleTex, _rampTex, _lutTex;
        private byte[] _primBytes = Array.Empty<byte>();
        private byte[] _groupBytes = Array.Empty<byte>();
        private byte[] _tileBytes = Array.Empty<byte>();
        private byte[] _candBytes = Array.Empty<byte>();
        private byte[] _featureBytes = Array.Empty<byte>();
        private byte[] _eyeBytes = Array.Empty<byte>();
        private byte[] _shadowBytes = Array.Empty<byte>();
        private byte[] _lutBytes = new byte[256 * 4];
        private CreaturePalette? _palette;
        private Image? _colorTableImg;
        private ImageTexture? _colorTableTex;
        private byte[] _colorTableBytes = new byte[16 * 6 * 4];

        private int _primRows = 1;
        private int _groupRows = 1;
        private bool _groupDirty = true;
        private double _lastFlash = double.NaN;
        private bool _ready;

        // diagnostics (benchmark harness)
        public static long UploadTicks;
        public static long PackTicks;

        public GpuCreatureRenderer(CreatureActor actor, Sprite2D sprite)
        {
            _actor = actor;
            _sprite = sprite;
            var pixelShader = GD.Load<Shader>(PixelShaderPath);
            var composeShader = GD.Load<Shader>(ComposeShaderPath);
            if (pixelShader == null || composeShader == null)
                throw new InvalidOperationException("GPU shaders not found");

            // Viewports are pooled, materials are not: every shader uniform (atlas, frame data,
            // palette, colour table) is per creature, so a shared material would make all
            // creatures render the last uploaded one.
            _viewport = GpuViewportPool.RentGbuffer(out _rect);

            actor.AddChild(_viewport);
            _viewport.AddChild(_rect);
            
            // Compose viewport/quad are per-creature (not pooled) due to per-creature shader params
            var composePair = GpuViewportPool.RentCompose();
            _outViewport = composePair.viewport;
            _outQuad = composePair.quad;
            actor.AddChild(_outViewport);
            _outViewport.AddChild(_outQuad);

            _outQuad.Texture = _viewport.GetTexture();

            _pixel = new ShaderMaterial { Shader = pixelShader };
            _rect.Material = _pixel;
            _compose = new ShaderMaterial { Shader = composeShader };
            _outQuad.Material = _compose;

            // the composed texture is premultiplied (blend_premul_alpha writes over a clear target)
            _premult = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.PremultAlpha };
            _sprite.Material = _premult;
            _sprite.TextureFilter = CanvasItem.TextureFilterEnum.Nearest;
            _sprite.Texture = _outViewport.GetTexture();
            _compose.SetShaderParameter("gbuffer", _viewport.GetTexture());
            _ready = true;
        }

        public void SetCanvas(CanvasSpec canvas)
        {
            Width = Math.Max(1, canvas.Width);
            Height = Math.Max(1, canvas.Height);
            OriginX = canvas.OriginX;
            OriginY = canvas.OriginY;
            _viewport.Size = new Vector2I(Width, Height);
            _rect.Position = Vector2.Zero;
            _rect.Size = new Vector2(Width, Height);
            _outViewport.Size = new Vector2I(Width, Height);
            _outQuad.Position = Vector2.Zero;
            _outQuad.Texture = _viewport.GetTexture();
            _compose.SetShaderParameter("gbuffer", _viewport.GetTexture());
            _compose.SetShaderParameter("frame_size", new Vector2(Width, Height));
            _sprite.Offset = new Vector2(-OriginX, -OriginY);
            _sprite.Texture = _outViewport.GetTexture();
            _pixel.SetShaderParameter("frame_size", new Vector2(Width, Height));
            _pixel.SetShaderParameter("frame_origin", new Vector2(OriginX, OriginY));
            _pixel.SetShaderParameter("tile_cols", (Width + GpuFrameData.TileSize - 1) / GpuFrameData.TileSize);
            _groupDirty = true;
        }

        /// <summary>Installs a freshly baked model: atlas, style table, ramp and the fixed data textures.</summary>
        public void ApplyModel(GpuModelBuild build, CreaturePalette palette = null)
        {
            Build = build;
            if (palette != null) _palette = palette;

            _atlasImg?.Dispose(); _atlasTex?.Dispose();
            _atlasImg = Image.CreateFromData(build.AtlasW, build.AtlasH, false, Image.Format.Rgba8, build.Atlas);
            _atlasTex = ImageTexture.CreateFromImage(_atlasImg);
            _pixel.SetShaderParameter("atlas_tex", _atlasTex);
            _pixel.SetShaderParameter("atlas_size", new Vector2(build.AtlasW, build.AtlasH));

            var styleBytes = new byte[build.Style.Length * 2];
            GpuTextures.ToHalfBytes(build.Style, build.Style.Length, styleBytes);
            _styleImg?.Dispose(); _styleTex?.Dispose();
            _styleImg = Image.CreateFromData(16, 2, false, Image.Format.Rgbah, styleBytes);
            _styleTex = ImageTexture.CreateFromImage(_styleImg);
            _pixel.SetShaderParameter("style_tex", _styleTex);

            // Build color table (16 slots x 6 levels) from palette (stored in _palette)
            // This is built once per model and updated if palette changes
            if (_palette != null) BuildColorTable(_palette);

            if (_rampImg == null || _rampImg.GetWidth() != 16 || _rampImg.GetHeight() != 8)
            {
                _rampImg?.Dispose(); _rampTex?.Dispose();
                _rampImg = Image.CreateEmpty(16, 8, false, Image.Format.R8);
                _rampTex = ImageTexture.CreateFromImage(_rampImg);
            }
            _rampImg.SetData(16, 8, false, Image.Format.R8, build.Ramp);
            _rampTex.Update(_rampImg);

            _primRows = Math.Max(1, build.PrimCount);
            _groupRows = Math.Max(1, Frame.GroupCount);
            GpuTextures.Ensure(ref _primImg, ref _primTex, ref _primBytes, GpuFrameData.PrimTexels, _primRows, Image.Format.Rgbah, 8);
            GpuTextures.Ensure(ref _groupImg, ref _groupTex, ref _groupBytes, GpuFrameData.GroupTexels, _groupRows, Image.Format.Rgbah, 8);
            GpuTextures.Ensure(ref _featureImg, ref _featureTex, ref _featureBytes, GpuFrameData.FeatureTexels, GpuFrameData.MaxFeatures, Image.Format.Rgbah, 8);
            GpuTextures.Ensure(ref _eyeImg, ref _eyeTex, ref _eyeBytes, GpuFrameData.EyeTile, GpuFrameData.EyeTile * GpuFrameData.MaxFeatures, Image.Format.R8, 1);
            GpuTextures.Ensure(ref _tileImg, ref _tileTex, ref _tileBytes, Frame.TileCols, Frame.TileRows, Image.Format.Rgbah, 8);
            GpuTextures.Ensure(ref _shadowImg, ref _shadowTex, ref _shadowBytes, Width, Height, Image.Format.R8, 1);
            _pixel.SetShaderParameter("prim_tex", _primTex);
            _pixel.SetShaderParameter("group_tex", _groupTex);
            _pixel.SetShaderParameter("tile_tex", _tileTex);
            _pixel.SetShaderParameter("feature_tex", _featureTex);
            _compose.SetShaderParameter("group_tex", _groupTex);
            _compose.SetShaderParameter("feature_tex", _featureTex);
            _compose.SetShaderParameter("eye_tex", _eyeTex);
            _compose.SetShaderParameter("shadow_tex", _shadowTex);
            _compose.SetShaderParameter("lut_tex", _lutTex);
            _compose.SetShaderParameter("color_table", _colorTableTex);
            _groupDirty = true;
        }

        /// <summary>Uploads one packed pose (main thread) and arms the G-buffer for exactly one render.</summary>
        public void Upload(CreaturePalette? palette, double flash, bool uploadData)
        {
            if (!_ready || Build == null) return;
            long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
            if (uploadData)
            {
                int primRows = Math.Max(1, Frame.PrimCount);
                if (primRows > _primRows)
                {
                    _primRows = primRows;
                    GpuTextures.Ensure(ref _primImg, ref _primTex, ref _primBytes, GpuFrameData.PrimTexels, _primRows, Image.Format.Rgbah, 8);
                    _pixel.SetShaderParameter("prim_tex", _primTex);
                }
                int primFloats = _primRows * GpuFrameData.PrimTexels * 4;
                if (Frame.PrimCount < _primRows)
                    Array.Clear(Frame.PrimRows, Frame.PrimCount * GpuFrameData.PrimTexels * 4,
                        (_primRows - Frame.PrimCount) * GpuFrameData.PrimTexels * 4);
                GpuTextures.ToHalfBytes(Frame.PrimRows, primFloats, _primBytes);
                GpuTextures.Upload(_primImg, _primTex, _primBytes, GpuFrameData.PrimTexels, _primRows, Image.Format.Rgbah);

                if (_groupDirty)
                {
                    GpuTextures.ToHalfBytes(Frame.GroupRows, _groupRows * GpuFrameData.GroupTexels * 4, _groupBytes);
                    GpuTextures.Upload(_groupImg, _groupTex, _groupBytes, GpuFrameData.GroupTexels, _groupRows, Image.Format.Rgbah);
                    _groupDirty = false;
                }

                GpuTextures.Ensure(ref _tileImg, ref _tileTex, ref _tileBytes, Frame.TileCols, Frame.TileRows, Image.Format.Rgbah, 8);
                GpuTextures.ToHalfBytes(Frame.TileRanges, Frame.TileCols * Frame.TileRows * 4, _tileBytes);
                GpuTextures.Upload(_tileImg, _tileTex, _tileBytes, Frame.TileCols, Frame.TileRows, Image.Format.Rgbah);

                int candTexels = Math.Max(1, Frame.CandidateTexels);
                int candRows = (candTexels + GpuFrameData.CandTexelsPerRow - 1) / GpuFrameData.CandTexelsPerRow;
                GpuTextures.Ensure(ref _candImg, ref _candTex, ref _candBytes, GpuFrameData.CandTexelsPerRow, candRows, Image.Format.Rgbah, 8);
                GpuTextures.ToHalfBytes(Frame.Candidates, candRows * GpuFrameData.CandTexelsPerRow * 4, _candBytes);
                GpuTextures.Upload(_candImg, _candTex, _candBytes, GpuFrameData.CandTexelsPerRow, candRows, Image.Format.Rgbah);
                _pixel.SetShaderParameter("cand_tex", _candTex);
                _pixel.SetShaderParameter("cand_texels_per_row", GpuFrameData.CandTexelsPerRow);

                GpuTextures.ToHalfBytes(Frame.FeatureRows, GpuFrameData.MaxFeatures * GpuFrameData.FeatureTexels * 4, _featureBytes);
                GpuTextures.Upload(_featureImg, _featureTex, _featureBytes, GpuFrameData.FeatureTexels, GpuFrameData.MaxFeatures, Image.Format.Rgbah);

                if (Frame.FeatureCount > 0)
                {
                    GpuTextures.Upload(_eyeImg, _eyeTex, Frame.EyeTiles, GpuFrameData.EyeTile,
                        GpuFrameData.EyeTile * GpuFrameData.MaxFeatures, Image.Format.R8);
                }

                if (Frame.ShadowMaskUsed)
                {
                    GpuTextures.Ensure(ref _shadowImg, ref _shadowTex, ref _shadowBytes, Width, Height, Image.Format.R8, 1);
                    Array.Copy(Frame.ShadowMask, _shadowBytes, Math.Min(Frame.ShadowMask.Length, _shadowBytes.Length));
                    GpuTextures.Upload(_shadowImg, _shadowTex, _shadowBytes, Width, Height, Image.Format.R8);
                }
            }

            // view uniforms
            var rows = Frame.ViewRows;
            _pixel.SetShaderParameter("ctv_row0", new Vector3(rows[0], rows[1], rows[2]));
            _pixel.SetShaderParameter("ctv_row1", new Vector3(rows[3], rows[4], rows[5]));
            _pixel.SetShaderParameter("ctv_row2", new Vector3(rows[6], rows[7], rows[8]));
            _pixel.SetShaderParameter("light_view", ToVector3(Frame.LightView));
            _pixel.SetShaderParameter("half_view", ToVector3(Frame.HalfView));
            _pixel.SetShaderParameter("lateral_view", ToVector3(Frame.LateralView));

            _compose.SetShaderParameter("feature_count", Frame.FeatureCount);
            _compose.SetShaderParameter("feature_bounds", new Vector4(
                Frame.FeatureX0, Frame.FeatureY0, Frame.FeatureX1, Frame.FeatureY1));
            _compose.SetShaderParameter("shadow_used", Frame.ShadowMaskUsed ? 1f : 0f);

            if (palette != null && (double.IsNaN(_lastFlash) || Math.Abs(flash - _lastFlash) > 1e-4))
            {
                _lastFlash = flash;
                palette.BuildLut(_lutBytes, flash);
                if (_lutImg == null || _lutImg.GetWidth() != 256 || _lutImg.GetHeight() != 1)
                {
                    _lutImg?.Dispose(); _lutTex?.Dispose();
                    _lutImg = Image.CreateEmpty(256, 1, false, Image.Format.Rgba8);
                    _lutTex = ImageTexture.CreateFromImage(_lutImg);
                    _compose.SetShaderParameter("lut_tex", _lutTex);
                }
                _lutImg.SetData(256, 1, false, Image.Format.Rgba8, _lutBytes);
                _lutTex!.Update(_lutImg);
            }

            if (uploadData)
            {
                _viewport.RenderTargetUpdateMode = SubViewport.UpdateMode.Once;
                _composePending = true;
            }
            UploadTicks += System.Diagnostics.Stopwatch.GetTimestamp() - t0;
        }

        /// <summary>
        /// Called once per display frame: arms the compose pass for the next render after a pose upload.
        /// The G-buffer viewport renders first (tree order), so the compose quad sees the new frame.
        /// </summary>
        public void TickCompose()
        {
            if (!_ready || !_composePending) return;
            _composePending = false;
            if (_sprite != null) _sprite.Visible = _sprite.Visible;
            _outViewport.RenderTargetUpdateMode = SubViewport.UpdateMode.Once;
        }

        private static Vector3 ToVector3(float[] v) => new Vector3(v[0], v[1], v[2]);

    /// <summary>Builds the 16x6 slot×level color table from the palette. Called once per model.</summary>
    public void BuildColorTable(CreaturePalette palette)
    {
        // color_table is 16 wide (slots 0..15), 6 high (levels 0..5)
        // Levels 6,7 map to 5 (highlight)
        var bytes = new byte[16 * 6 * 4];
        for (int slot = 0; slot < 16; slot++)
        {
            for (int level = 0; level < 6; level++)
            {
                var color = palette.Color((MaterialSlot)Math.Min(slot, 12), level);
                int idx = (level * 16 + slot) * 4;
                // Premultiply alpha
                float a = color.A / 255.0f;
                bytes[idx + 0] = (byte)(color.R * a);
                bytes[idx + 1] = (byte)(color.G * a);
                bytes[idx + 2] = (byte)(color.B * a);
                bytes[idx + 3] = color.A;
            }
        }
        _colorTableBytes = bytes;
        if (_colorTableImg == null || _colorTableImg.GetWidth() != 16 || _colorTableImg.GetHeight() != 6)
        {
            _colorTableImg?.Dispose(); _colorTableTex?.Dispose();
            _colorTableImg = Image.CreateFromData(16, 6, false, Image.Format.Rgba8, bytes);
            _colorTableTex = ImageTexture.CreateFromImage(_colorTableImg);
        }
        else
        {
            _colorTableImg.SetData(16, 6, false, Image.Format.Rgba8, bytes);
            _colorTableTex!.Update(_colorTableImg);
        }
        _compose.SetShaderParameter("color_table", _colorTableTex);
    }

    /// <summary>
    /// Applies a distance LOD level. Colours are never degraded: level 1 simply freezes the last
    /// composed frame (no shader work at all), level 2 hides the sprite. Both levels are only
    /// reached well outside the camera, so the player never sees a quality change.
    /// </summary>
    public void SetLod(int lod)
    {
        if (!_ready) return;
        switch (lod)
        {
            case 0: // full quality: re-render G-buffer + compose at the animation rate
                if (_sprite.Texture != _outViewport.GetTexture()) _sprite.Texture = _outViewport.GetTexture();
                _sprite.Material = _premult;
                _sprite.Modulate = Colors.White;
                _composePending = true;
                break;
            case 1: // frozen: keep the last composed frame, run no shaders
                _sprite.Texture = _outViewport.GetTexture();
                _sprite.Material = _premult;
                _sprite.Modulate = Colors.White;
                _composePending = false;
                break;
            case 2: // hidden
                _composePending = false;
                break;
        }
    }

    public void Dispose()
        {
            _ready = false;
            if (GodotObject.IsInstanceValid(_sprite)) _sprite.Texture = null;
            if (GodotObject.IsInstanceValid(_sprite)) _sprite.Material = null;
            if (GodotObject.IsInstanceValid(_viewport))
            {
                GpuViewportPool.ReturnGbuffer(_viewport, _rect, _actor);
            }
            if (GodotObject.IsInstanceValid(_outViewport))
            {
                GpuViewportPool.ReturnCompose(_outViewport, _outQuad, _actor);
            }
            _primImg?.Dispose(); _primTex?.Dispose();
            _groupImg?.Dispose(); _groupTex?.Dispose();
            _tileImg?.Dispose(); _tileTex?.Dispose();
            _candImg?.Dispose(); _candTex?.Dispose();
            _featureImg?.Dispose(); _featureTex?.Dispose();
            _eyeImg?.Dispose(); _eyeTex?.Dispose();
            _shadowImg?.Dispose(); _shadowTex?.Dispose();
            _atlasImg?.Dispose(); _atlasTex?.Dispose();
            _styleImg?.Dispose(); _styleTex?.Dispose();
            _rampImg?.Dispose(); _rampTex?.Dispose();
            _lutImg?.Dispose(); _lutTex?.Dispose();
            _colorTableImg?.Dispose(); _colorTableTex?.Dispose();
            _compose.Dispose();
            _pixel.Dispose();
            _premult.Dispose();
        }
    }
}
