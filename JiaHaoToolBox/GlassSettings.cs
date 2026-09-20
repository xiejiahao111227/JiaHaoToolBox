using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace WpfApp1
{
    // 界面偏好：深浅色 + 动效总开关与分项开关。外观只有液态玻璃一档，不再存档位。
    // 在 App.OnStartup 里读，早于主窗口构造，避免启动瞬间先闪一套别的配色。
    // 旧版本只有 %LOCALAPPDATA%\JiaHaoTool\theme.txt（内容 Light/Dark），首次读不到
    // settings.txt 时从它迁移一次深色偏好。
    public sealed class GlassSettings
    {
        public bool Dark;
        public bool Motion = true;
        public bool MotionSpring = true;
        public bool MotionEnter = true;
        public bool MotionBackdrop = true;
        public bool MotionShimmer = true;
        public bool MotionBreathe = true;

        public static GlassSettings Current { get; private set; } = Load();

        private static string PrefDir => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JiaHaoTool");

        private static string PrefPath => Path.Combine(PrefDir, "settings.txt");

        // 设置页要把完整路径显示给用户，让用户知道偏好存在哪、坏了去哪删
        public static string PreferencePath => PrefPath;

        private static string LegacyThemePath => Path.Combine(PrefDir, "theme.txt");

        private static bool ParseBool(string value, bool fallback)
        {
            if (value == "1" || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)) return true;
            if (value == "0" || string.Equals(value, "false", StringComparison.OrdinalIgnoreCase)) return false;
            return fallback;
        }

        public static GlassSettings Load()
        {
            var s = new GlassSettings();
            try
            {
                foreach (var line in File.ReadAllLines(PrefPath))
                {
                    var i = line.IndexOf('=');
                    if (i <= 0) continue;
                    var key = line.Substring(0, i).Trim();
                    var value = line.Substring(i + 1).Trim();
                    switch (key)
                    {
                        case "theme": s.Dark = string.Equals(value, "Dark", StringComparison.OrdinalIgnoreCase); break;
                        case "motion": s.Motion = ParseBool(value, true); break;
                        case "motion.spring": s.MotionSpring = ParseBool(value, true); break;
                        case "motion.enter": s.MotionEnter = ParseBool(value, true); break;
                        case "motion.backdrop": s.MotionBackdrop = ParseBool(value, true); break;
                        case "motion.shimmer": s.MotionShimmer = ParseBool(value, true); break;
                        case "motion.breathe": s.MotionBreathe = ParseBool(value, true); break;
                    }
                }
            }
            catch
            {
                // 读不到就用默认值，不影响启动
            }

            try
            {
                if (!File.Exists(PrefPath) &&
                    string.Equals(File.ReadAllText(LegacyThemePath).Trim(), "Dark", StringComparison.OrdinalIgnoreCase))
                {
                    s.Dark = true;
                }
            }
            catch
            {
            }

            return s;
        }

        public void Save()
        {
            var lines = new List<string>
            {
                "theme=" + (Dark ? "Dark" : "Light"),
                "motion=" + (Motion ? 1 : 0),
                "motion.spring=" + (MotionSpring ? 1 : 0),
                "motion.enter=" + (MotionEnter ? 1 : 0),
                "motion.backdrop=" + (MotionBackdrop ? 1 : 0),
                "motion.shimmer=" + (MotionShimmer ? 1 : 0),
                "motion.breathe=" + (MotionBreathe ? 1 : 0),
            };
            try
            {
                Directory.CreateDirectory(PrefDir);
                File.WriteAllText(PrefPath, string.Join(Environment.NewLine, lines) + Environment.NewLine, new UTF8Encoding(false));
            }
            catch
            {
                // 写不进偏好只影响下次启动的默认值
            }
        }

        public void ResetToDefault()
        {
            Dark = false;
            Motion = true;
            MotionSpring = true;
            MotionEnter = true;
            MotionBackdrop = true;
            MotionShimmer = true;
            MotionBreathe = true;
        }

        public void ApplyToMotion()
        {
            GlassMotion.SpringEnabled = Motion && MotionSpring;
            GlassMotion.EnterEnabled = Motion && MotionEnter;
            GlassMotion.BackdropEnabled = Motion && MotionBackdrop;
            GlassMotion.ShimmerEnabled = Motion && MotionShimmer;
            GlassMotion.BreatheEnabled = Motion && MotionBreathe;
        }
    }
}
