using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using WpfApp1;

namespace ShimmerHarness
{
    // 动效判定的离线台：只编进产品的 GlassMotion.cs，自己造进度条与状态灯，
    // 隔时把面板渲染成位图比像素，验证「在推进才扫光、空闲/跑满不扫、呼吸只作用于该呼吸的那盏」。
    public static class Program
    {
        private class Case
        {
            public string Name;
            public FrameworkElement Element;
            public Func<bool> ExpectMoving;
            public bool SkipWhenShimmerOff;
        }

        private static Window window;
        private static StackPanel panel;
        private static DispatcherTimer timer;
        private static int step;
        private static bool shimmerOn = true;
        private static BitmapSource baseline;
        private static readonly System.Collections.Generic.List<Case> cases = new();

        [STAThread]
        public static void Main()
        {
            var app = new Application();
            GlassMotion.RegisterGlobalProgressBarMotion();

            panel = new StackPanel { Background = Brushes.White };
            var idle = AddBar("空闲 0%", 0);
            var mid = AddBar("推进 45%", 45);
            var full = AddBar("跑满 100%", 100);
            var indeterminate = new ProgressBar
            {
                Width = 440,
                Height = 22,
                Margin = new Thickness(20, 2, 20, 2),
                IsIndeterminate = true
            };
            panel.Children.Add(Label("不确定态"));
            panel.Children.Add(indeterminate);

            var breathingLamp = MakeLamp();
            var stillLamp = MakeLamp();
            var lamps = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(20, 2, 20, 6) };
            lamps.Children.Add(breathingLamp);
            lamps.Children.Add(stillLamp);
            panel.Children.Add(Label("底栏状态灯：呼吸 / 静止"));
            panel.Children.Add(lamps);
            GlassMotion.SetBreathe(breathingLamp, true);
            GlassMotion.SetBreathe(stillLamp, false);

            cases.Add(new Case { Name = "空闲 0%", Element = idle, ExpectMoving = () => false });
            cases.Add(new Case { Name = "推进 45%", Element = mid, ExpectMoving = () => shimmerOn });
            cases.Add(new Case { Name = "跑满 100%", Element = full, ExpectMoving = () => false });
            // 不确定态的进度条自带官方扫光动画，关掉我们的叠加层它照样在动
            cases.Add(new Case { Name = "不确定态", Element = indeterminate, ExpectMoving = () => true, SkipWhenShimmerOff = true });
            cases.Add(new Case { Name = "呼吸灯", Element = breathingLamp, ExpectMoving = () => GlassMotion.BreatheEnabled });
            cases.Add(new Case { Name = "静止灯", Element = stillLamp, ExpectMoving = () => false });

            window = new Window
            {
                Title = "ShimmerHarness",
                Content = panel,
                Width = 500,
                Height = 400,
                WindowStartupLocation = WindowStartupLocation.CenterScreen,
                ShowInTaskbar = false
            };
            window.Loaded += (s, e) =>
            {
                timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(900) };
                timer.Tick += OnTick;
                timer.Start();
            };
            window.Show();
            app.Run();
        }

        private static ProgressBar AddBar(string name, double value)
        {
            var bar = new ProgressBar
            {
                Width = 440,
                Height = 22,
                Margin = new Thickness(20, 2, 20, 2),
                Minimum = 0,
                Maximum = 100,
                Value = value
            };
            panel.Children.Add(Label(name));
            panel.Children.Add(bar);
            return bar;
        }

        private static UIElement Label(string text)
        {
            return new TextBlock { Text = text, Margin = new Thickness(20, 6, 20, 0), FontSize = 12 };
        }

        private static FrameworkElement MakeLamp()
        {
            return new Ellipse
            {
                Width = 14,
                Height = 14,
                Margin = new Thickness(0, 0, 12, 0),
                Fill = new SolidColorBrush(Color.FromRgb(125, 255, 159))
            };
        }

        private static BitmapSource Grab()
        {
            var w = (int)Math.Ceiling(panel.ActualWidth);
            var h = (int)Math.Ceiling(panel.ActualHeight);
            var bmp = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
            bmp.Render(panel);
            bmp.Freeze();
            return bmp;
        }

        private static int ChangedPixels(BitmapSource a, BitmapSource b, FrameworkElement fe)
        {
            var origin = fe.TranslatePoint(new Point(0, 0), panel);
            var left = Math.Max(0, (int)Math.Floor(origin.X));
            var top = (int)Math.Floor(origin.Y);
            var width = Math.Min((int)Math.Floor(fe.ActualWidth), a.PixelWidth - left);
            var height = (int)Math.Floor(fe.ActualHeight);
            if (width <= 0 || height <= 0 || top < 0 || top + height > a.PixelHeight) return -1;
            var stride = width * 4;
            var ba = new byte[width * height * 4];
            var bb = new byte[width * height * 4];
            a.CopyPixels(new Int32Rect(left, top, width, height), ba, stride, 0);
            b.CopyPixels(new Int32Rect(left, top, width, height), bb, stride, 0);
            var changed = 0;
            for (var i = 0; i < ba.Length; i += 4)
            {
                var d = Math.Abs(ba[i] - bb[i]) + Math.Abs(ba[i + 1] - bb[i + 1]) + Math.Abs(ba[i + 2] - bb[i + 2]);
                if (d > 3) changed++;
            }
            return changed;
        }

        private static void Report(string phase, BitmapSource a, BitmapSource b)
        {
            Console.WriteLine($"[{phase}] 动效={shimmerOn} 采样间隔 1.8s");
            foreach (var item in cases)
            {
                if (!shimmerOn && item.SkipWhenShimmerOff)
                {
                    Console.WriteLine($"  {item.Name,-10} 跳过（控件自带动画）");
                    continue;
                }
                var changed = ChangedPixels(a, b, item.Element);
                var expect = item.ExpectMoving();
                var verdict = (changed > 20) == expect ? "OK" : "FAIL";
                Console.WriteLine($"  {item.Name,-10} 变化像素 {changed,6}  期望 {(expect ? "在动" : "静止")}  {verdict}");
            }
        }

        private static void OnTick(object sender, EventArgs e)
        {
            step++;
            var now = Grab();
            switch (step)
            {
                case 1:
                    baseline = now;
                    return;
                case 3:
                    Report("全部动效开启", baseline, now);
                    shimmerOn = false;
                    GlassMotion.SpringEnabled = false;
                    GlassMotion.EnterEnabled = false;
                    GlassMotion.BackdropEnabled = false;
                    GlassMotion.ShimmerEnabled = false;
                    GlassMotion.BreatheEnabled = false;
                    GlassMotion.StopContinuousMotion();
                    return;
                case 4:
                    baseline = now;
                    return;
                case 6:
                    Report("总开关关闭", baseline, now);
                    Console.WriteLine("done");
                    timer.Stop();
                    window.Close();
                    return;
            }
        }
    }
}
