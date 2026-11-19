// Procedural Pixel Creatures - global rasterization budget.
//
// A creature re-rasterizes only at its animation frame rate, so with N creatures on screen the
// renderer is asked for N * AnimationFps creature frames per second. On weak hardware (Raspberry
// Pi 4 and similar) that demand can exceed what the GPU can deliver, which shows up as a low
// display frame rate.
//
// This budget measures how many creature frames per second are actually being produced and, when
// that exceeds the configured cap, stretches every actor's animation interval. Only the *update
// rate* is reduced - the image itself is never degraded, so colours, outlines and shading stay
// exactly as they are (unlike a resolution or palette LOD).
//
// Set MaxRendersPerSecond to 0 to disable the budget entirely.

using System;
using Godot;

namespace PixelCreatures.Runtime
{
    public static class CreatureRasterBudget
    {
        /// <summary>Creature frames per second the renderer may produce. 0 disables the budget.</summary>
        public static int MaxRendersPerSecond = 260;

        /// <summary>Largest interval stretch the budget may apply (8 = at most eight times slower).</summary>
        public static double MaxStretch = 8.0;

        // measured production rate, exponentially smoothed
        private static double _rate;
        private static int _count;
        private static double _windowTime;
        private static ulong _lastFrame;
        private static double _stretch = 1.0;

        /// <summary>Multiplier applied to every actor's animation interval (1 = no throttling).</summary>
        public static double Stretch => _stretch;

        /// <summary>Measured creature frames per second (smoothed).</summary>
        public static double Rate => _rate;

        /// <summary>Called once by every actor that rasterizes a frame.</summary>
        internal static void ReportRender()
        {
            _count++;
        }

        /// <summary>Advances the control loop once per display frame.</summary>
        internal static void Tick(double delta)
        {
            ulong frame = Engine.GetProcessFrames();
            if (frame == _lastFrame) return;
            _lastFrame = frame;

            if (MaxRendersPerSecond <= 0)
            {
                _stretch = 1.0;
                _count = 0;
                _rate = 0;
                return;
            }

            if (delta <= 0 || double.IsNaN(delta)) return;
            _windowTime += delta;
            if (_windowTime < 0.25) return;

            double sample = _count / _windowTime;
            _count = 0;
            _windowTime = 0;
            // 0.4 keeps the measurement responsive without letting a single hitch spike the stretch
            _rate = _rate <= 0 ? sample : _rate * 0.6 + sample * 0.4;

            double load = _rate / MaxRendersPerSecond;
            // integral controller: the stretch settles where the produced rate matches the cap
            _stretch = Math.Clamp(_stretch + (load - 1.0) * 1.5, 1.0, Math.Max(1.0, MaxStretch));
        }

        /// <summary>Resets the measured state (used by tests and the benchmark harness).</summary>
        public static void Reset()
        {
            _rate = 0;
            _count = 0;
            _windowTime = 0;
            _stretch = 1.0;
        }

        /// <summary>
        /// Interval multiplier for one actor: the shared budget stretch, plus a size based term so a
        /// creature covering only a few dozen pixels is refreshed less often than a large one. The
        /// latter is imperceptible (the sprite is tiny) and keeps crowds of distant animals cheap.
        /// </summary>
        public static double IntervalScaleFor(int canvasWidth, int canvasHeight)
        {
            double area = Math.Max(1, canvasWidth * canvasHeight);
            double sizeFactor = Math.Clamp(2500.0 / area, 1.0, 3.0);
            return _stretch * sizeFactor;
        }
    }
}
