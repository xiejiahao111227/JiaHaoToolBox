using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace WpfApp1
{
    // 「工具设置」页：深浅色与动效总开关/分项开关。全部即时生效 + 立即落盘（GlassSettings），
    // 下次启动由 App.OnStartup 提前读回，所以启动过程中不会先闪一套别的配色。
    public partial class MainWindow
    {
        private void ToolSettingsButton_Click(object sender, RoutedEventArgs e)
        {
            ShowPage("ToolSettingsView");
            SyncInterfaceSettingToggles();
            UpdateButtonStates("ToolSettings");
        }

        // PageHostGrid 的直接子 Grid 就是一个页面，底栏那几个 StackPanel 在旁边的 Border 里、不归它管，
        // 所以整片收掉是安全的。不能只挑挂了 GlassPageStyle 的——RomDownloadview 就没有那个样式，
        // 按样式过滤会让它留在设置页底下透出来。
        private void ShowPage(string targetName)
        {
            if (PageHostGrid != null)
            {
                foreach (var child in PageHostGrid.Children)
                {
                    if (!(child is Grid page)) continue;
                    if (string.Equals(page.Name, targetName, StringComparison.Ordinal)) continue;
                    page.Visibility = Visibility.Collapsed;
                }
            }
            var target = this.FindName(targetName) as Grid;
            if (target != null)
            {
                target.Visibility = Visibility.Visible;
                GlassMotion.FadeIn(target);
            }
        }

        private void InterfaceSetting_Changed(object sender, RoutedEventArgs e)
        {
            var s = GlassSettings.Current;
            bool previousDark = s.Dark;
            bool previousMotion = s.Motion;

            s.Dark = IsToggleOn(DarkModeToggle);
            s.Motion = IsToggleOn(MotionMasterToggle);
            s.MotionSpring = IsToggleOn(MotionSpringToggle);
            s.MotionEnter = IsToggleOn(MotionEnterToggle);
            s.MotionBackdrop = IsToggleOn(MotionBackdropToggle);
            s.MotionShimmer = IsToggleOn(MotionShimmerToggle);
            s.MotionBreathe = IsToggleOn(MotionBreatheToggle);
            s.Save();
            s.ApplyToMotion();

            // 关掉的这一项正在跑的常驻动画要当场停，不能等下一次换主题
            if (previousMotion && !s.Motion) GlassMotion.StopContinuousMotion();

            // 深浅色只影响字典内容，不换字典结构；但光斑动画挂在旧字典上，必须重挂
            ApplyGlassTheme();
            if (previousDark != s.Dark) GlassMotion.FadeIn(MainContentBorder);
            SyncInterfaceSettingToggles();
            AddLogMessage("系统", DescribeInterfaceSetting(s, sender as ToggleButton));
        }

        private static bool IsToggleOn(ToggleButton toggle)
        {
            return toggle != null && toggle.IsChecked == true;
        }

        private string DescribeInterfaceSetting(GlassSettings s, ToggleButton changed)
        {
            if (changed == null) return "界面设置已更新";
            if (ReferenceEquals(changed, DarkModeToggle)) return s.Dark ? "已切换到深色主题" : "已切换到浅色主题";
            if (ReferenceEquals(changed, MotionMasterToggle)) return s.Motion ? "已开启全部动效" : "已关闭全部动效";
            string name = ReferenceEquals(changed, MotionSpringToggle) ? "按钮弹性"
                : ReferenceEquals(changed, MotionEnterToggle) ? "页面入场"
                : ReferenceEquals(changed, MotionBackdropToggle) ? "背景光斑漂移"
                : ReferenceEquals(changed, MotionShimmerToggle) ? "进度条流光"
                : ReferenceEquals(changed, MotionBreatheToggle) ? "状态灯呼吸" : "该项";
            return "已" + (s.Motion && ToggleValue(s, changed) ? "开启" : "关闭") + name;
        }

        private bool ToggleValue(GlassSettings s, ToggleButton changed)
        {
            if (ReferenceEquals(changed, MotionSpringToggle)) return s.MotionSpring;
            if (ReferenceEquals(changed, MotionEnterToggle)) return s.MotionEnter;
            if (ReferenceEquals(changed, MotionBackdropToggle)) return s.MotionBackdrop;
            if (ReferenceEquals(changed, MotionShimmerToggle)) return s.MotionShimmer;
            if (ReferenceEquals(changed, MotionBreatheToggle)) return s.MotionBreathe;
            return s.Motion;
        }

        // 从 GlassSettings 回灌到界面上：总开关关掉时分项置灰但仍显示各自的值，
        // 免得一关总开关就把用户原本的分项偏好抹掉。
        private void SyncInterfaceSettingToggles()
        {
            var s = GlassSettings.Current;
            if (DarkModeToggle != null) DarkModeToggle.IsChecked = s.Dark;
            if (MotionMasterToggle != null) MotionMasterToggle.IsChecked = s.Motion;
            SyncMotionSubToggle(MotionSpringToggle, s.MotionSpring);
            SyncMotionSubToggle(MotionEnterToggle, s.MotionEnter);
            SyncMotionSubToggle(MotionBackdropToggle, s.MotionBackdrop);
            SyncMotionSubToggle(MotionShimmerToggle, s.MotionShimmer);
            SyncMotionSubToggle(MotionBreatheToggle, s.MotionBreathe);
            if (SettingsPathText != null) SettingsPathText.Text = GlassSettings.PreferencePath;
        }

        private void SyncMotionSubToggle(ToggleButton toggle, bool value)
        {
            if (toggle == null) return;
            toggle.IsChecked = value;
            toggle.IsEnabled = GlassSettings.Current.Motion;
        }

        private void ResetInterfaceSettingsButton_Click(object sender, RoutedEventArgs e)
        {
            var s = GlassSettings.Current;
            s.ResetToDefault();
            s.Save();
            s.ApplyToMotion();
            ApplyGlassTheme();
            SyncInterfaceSettingToggles();
            AddLogMessage("系统", "界面设置已恢复默认");
        }
    }
}
