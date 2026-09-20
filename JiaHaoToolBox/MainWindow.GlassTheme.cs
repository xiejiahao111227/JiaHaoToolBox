using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Application = System.Windows.Application;

namespace WpfApp1
{
    // 语义画刷字典的整本替换：App.xaml 里最后一本可以是浅色玻璃或深色玻璃。
    // 它排在 HandyControl 主题之后，因此除了自定义的 Glass* 键，玻璃这两本还覆盖了 RegionBrush、
    // PrimaryTextBrush 等 HandyControl 画刷键——HandyControl 的画刷是冻结的，改颜色键没用，
    // 只能整本换掉画刷本身，ComboBox、SideMenu 这类控件才会跟着换色。
    public partial class MainWindow
    {
        // App.xaml 里最后一本：前面依次是 Icons、HandyControl 的 SkinDefault 与 Theme、圆角刻度字典
        private const int GlassThemeDictionaryIndex = 4;
        private const string GlassThemeLightSource = "Theme/Glass.Light.xaml";
        private const string GlassThemeDarkSource = "Theme/Glass.Dark.xaml";

        // App.OnStartup 在建主窗口之前调用，避免启动瞬间先闪一套别的配色。
        public static void ApplyThemeDictionary(GlassSettings settings)
        {
            var merged = Application.Current.Resources.MergedDictionaries;
            if (merged.Count <= GlassThemeDictionaryIndex) return;
            merged[GlassThemeDictionaryIndex] = new ResourceDictionary
            {
                Source = new Uri("pack://application:,,,/" +
                    (settings.Dark ? GlassThemeDarkSource : GlassThemeLightSource), UriKind.Absolute)
            };
        }

        private void ApplyGlassTheme()
        {
            ApplyThemeDictionary(GlassSettings.Current);
            StartGlassBackdropDrift();
            UpdateGlassThemeToggle();
        }

        // 构造函数里调用：字典已由 App.OnStartup 换好，这里只补光斑动画与按钮图形。
        private void InitializeGlassTheme()
        {
            StartGlassBackdropDrift();
            UpdateGlassThemeToggle();
        }

        // 背景光斑缓慢漂移 + 指针视差：字典会把塞进来的 Freezable 冻结掉，所以先在克隆体上起好动画
        // （带活动的动画就无法冻结），再放回字典；换主题整本字典被替换，因此每次都要重挂。
        // 位移挂在 RelativeTransform 上而不是 Transform：后者是绝对像素，零点几根本看不出来。
        private void StartGlassBackdropDrift()
        {
            var s = GlassSettings.Current;
            if (!s.Motion || !s.MotionBackdrop)
            {
                GlassMotion.UnbindBackdropParallax();
                return;
            }

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

        private void UpdateGlassThemeToggle()
        {
            bool dark = GlassSettings.Current.Dark;
            if (GlassThemeToggleGlyph != null)
            {
                GlassThemeToggleGlyph.Text = dark ? "\uE706" : "\uE708";
                GlassMotion.Pop(GlassThemeToggleGlyph);
            }
            if (GlassThemeToggleButton != null)
                GlassThemeToggleButton.ToolTip = dark ? "切换到浅色玻璃主题" : "切换到深色玻璃主题";
        }

        private void GlassThemeToggleButton_Click(object sender, RoutedEventArgs e)
        {
            GlassSettings.Current.Dark = !GlassSettings.Current.Dark;
            GlassSettings.Current.Save();
            ApplyGlassTheme();
            GlassMotion.FadeIn(MainContentBorder);
            AddLogMessage("系统", GlassSettings.Current.Dark ? "已切换到深色玻璃主题" : "已切换到浅色玻璃主题");
        }
    }
}
