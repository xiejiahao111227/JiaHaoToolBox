using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Application = System.Windows.Application;
using Path = System.IO.Path;

namespace WpfApp1
{
    // 液态玻璃主题的浅色/深色切换：整本替换 App.xaml 里最后一本语义画刷字典。
    // 它排在 HandyControl 主题之后，因此除了自定义的 Glass* 键，还覆盖了 RegionBrush、
    // PrimaryTextBrush 等 HandyControl 画刷键——HandyControl 的画刷是冻结的，改颜色键没用，
    // 只能整本换掉画刷本身，ComboBox、SideMenu 这类控件才会跟着换色。
    public partial class MainWindow
    {
        private const int GlassThemeDictionaryIndex = 3;
        private const string GlassThemeLightSource = "Theme/Glass.Light.xaml";
        private const string GlassThemeDarkSource = "Theme/Glass.Dark.xaml";

        private static string GlassThemePreferenceFile => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "JiaHaoTool",
            "theme.txt");

        private bool IsGlassThemeDark
        {
            get
            {
                var merged = Application.Current.Resources.MergedDictionaries;
                if (merged.Count <= GlassThemeDictionaryIndex) return false;
                return (merged[GlassThemeDictionaryIndex].Source?.OriginalString ?? "")
                    .EndsWith("Glass.Dark.xaml", StringComparison.OrdinalIgnoreCase);
            }
        }

        private void ApplyGlassTheme(bool dark)
        {
            var merged = Application.Current.Resources.MergedDictionaries;
            if (merged.Count <= GlassThemeDictionaryIndex) return;
            merged[GlassThemeDictionaryIndex] = new ResourceDictionary
            {
                Source = new Uri("pack://application:,,,/" + (dark ? GlassThemeDarkSource : GlassThemeLightSource), UriKind.Absolute)
            };
            StartGlassBackdropDrift();
            UpdateGlassThemeToggle(dark);
        }

        // 背景光斑缓慢漂移 + 指针视差：字典会把塞进来的 Freezable 冻结掉，所以先在克隆体上起好动画
        // （带活动的动画就无法冻结），再放回字典；换主题整本字典被替换，因此每次都要重挂。
        // 位移挂在 RelativeTransform 上而不是 Transform：后者是绝对像素，零点几根本看不出来。
        private void StartGlassBackdropDrift()
        {
            var merged = Application.Current.Resources.MergedDictionaries;
            if (merged.Count <= GlassThemeDictionaryIndex) return;
            var dict = merged[GlassThemeDictionaryIndex];
            if (!(dict["GlassBackdrop"] is ImageBrush source)) return;
            var brush = source.Clone();
            var zoom = new ScaleTransform(1.14, 1.14, 0.5, 0.5);
            var drift = new TranslateTransform();
            var parallax = new TranslateTransform();
            var transform = new TransformGroup();
            transform.Children.Add(zoom);
            transform.Children.Add(drift);
            transform.Children.Add(parallax);
            brush.RelativeTransform = transform;
            drift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-0.014, 0.014, TimeSpan.FromSeconds(19))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
            });
            drift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0.011, -0.013, TimeSpan.FromSeconds(25))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
            });
            dict["GlassBackdrop"] = brush;
            GlassMotion.BindBackdropParallax(MainContentBorder, parallax);
        }

        private void UpdateGlassThemeToggle(bool dark)
        {
            if (GlassThemeToggleGlyph != null)
            {
                GlassThemeToggleGlyph.Text = dark ? "\uE706" : "\uE708";
                GlassMotion.Pop(GlassThemeToggleGlyph);
            }
            if (GlassThemeToggleButton != null)
                GlassThemeToggleButton.ToolTip = dark ? "切换到浅色玻璃主题" : "切换到深色玻璃主题";
        }

        // 构造函数里调用，早于窗口绘制，避免启动时闪一下另一种配色
        private void RestoreGlassTheme()
        {
            bool dark = false;
            try
            {
                dark = string.Equals(File.ReadAllText(GlassThemePreferenceFile).Trim(), "Dark", StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                // 偏好读不到就用默认浅色
            }
            if (dark) ApplyGlassTheme(true);
            else StartGlassBackdropDrift();
        }

        private void GlassThemeToggleButton_Click(object sender, RoutedEventArgs e)
        {
            bool dark = !IsGlassThemeDark;
            ApplyGlassTheme(dark);
            GlassMotion.FadeIn(MainContentBorder);
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(GlassThemePreferenceFile));
                File.WriteAllText(GlassThemePreferenceFile, dark ? "Dark" : "Light");
            }
            catch
            {
                // 写不进偏好不影响本次切换
            }
            AddLogMessage("系统", dark ? "已切换到深色玻璃主题" : "已切换到浅色玻璃主题");
        }
    }
}
