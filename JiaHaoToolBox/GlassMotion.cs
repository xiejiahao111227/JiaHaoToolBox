using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Border = System.Windows.Controls.Border;
using ButtonBase = System.Windows.Controls.Primitives.ButtonBase;
using Color = System.Windows.Media.Color;
using ProgressBar = System.Windows.Controls.ProgressBar;
using MouseEventHandler = System.Windows.Input.MouseEventHandler;
using MouseButtonEventHandler = System.Windows.Input.MouseButtonEventHandler;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;

namespace WpfApp1
{
    // 液态玻璃动效：悬停/按下的弹性缩放、页面淡入上滑、主题切换淡入、进度条流光、状态灯呼吸。
    // 全部走 RenderTransform + 画刷 RelativeTransform（GPU 合成层），不引入运行时模糊，启动耗时不受影响。
    //
    // 开关来自「工具设置」页（见 GlassSettings）：总开关关掉时各入口直接返回，常驻动画还会被显式停掉，
    // 否则一次性动画（弹性、入场）自己会跑完，只有 Forever 的漂移/流光会赖着不动。
    public static class GlassMotion
    {
        public static bool SpringEnabled = true;
        public static bool EnterEnabled = true;
        public static bool BackdropEnabled = true;
        public static bool ShimmerEnabled = true;
        public static bool BreatheEnabled = true;

        private static readonly DependencyProperty ScaleOwnerProperty = DependencyProperty.RegisterAttached(
            "ScaleOwner", typeof(ScaleTransform), typeof(GlassMotion));

        private static readonly DependencyProperty AttachedProperty = DependencyProperty.RegisterAttached(
            "Attached", typeof(bool), typeof(GlassMotion));

        public static readonly DependencyProperty LiftProperty = DependencyProperty.RegisterAttached(
            "Lift", typeof(bool), typeof(GlassMotion), new PropertyMetadata(false, OnLiftChanged));

        public static void SetLift(DependencyObject element, bool value) => element.SetValue(LiftProperty, value);
        public static bool GetLift(DependencyObject element) => (bool)element.GetValue(LiftProperty);

        public static readonly DependencyProperty EnterProperty = DependencyProperty.RegisterAttached(
            "Enter", typeof(bool), typeof(GlassMotion), new PropertyMetadata(false, OnEnterChanged));

        public static void SetEnter(DependencyObject element, bool value) => element.SetValue(EnterProperty, value);
        public static bool GetEnter(DependencyObject element) => (bool)element.GetValue(EnterProperty);

        private static void OnLiftChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is not UIElement uie || !(bool)e.NewValue) return;
            if ((bool)uie.GetValue(AttachedProperty)) return;
            uie.SetValue(AttachedProperty, true);
            uie.MouseEnter += (_, _) => AnimateScale(uie, 1.014, 0.22, EasingMode.EaseOut, new BackEase { Amplitude = 0.25 });
            uie.MouseLeave += (_, _) => AnimateScale(uie, 1.0, 0.26, EasingMode.EaseOut, new CircleEase());
        }

        private static void OnEnterChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            if (d is not FrameworkElement fe || !(bool)e.NewValue) return;
            fe.IsVisibleChanged += (_, args) =>
            {
                if (args.NewValue is not true) return;
                PlayEnter(fe);
            };
        }

        // 按钮全局弹性：类处理器一次注册，覆盖 18 个页面里所有 ButtonBase，不用逐个改按钮样式
        public static void RegisterGlobalButtonMotion()
        {
            EventManager.RegisterClassHandler(typeof(ButtonBase), UIElement.MouseEnterEvent, new MouseEventHandler(
                (s, _) => AnimateScale((UIElement)s, 1.045, 0.16, EasingMode.EaseOut, new BackEase { Amplitude = 0.4 })));
            EventManager.RegisterClassHandler(typeof(ButtonBase), UIElement.MouseLeaveEvent, new MouseEventHandler(
                (s, _) => AnimateScale((UIElement)s, 1.0, 0.2, EasingMode.EaseOut, new CircleEase())));
            EventManager.RegisterClassHandler(typeof(ButtonBase), UIElement.PreviewMouseLeftButtonDownEvent, new MouseButtonEventHandler(
                (s, _) => AnimateScale((UIElement)s, 0.955, 0.09, EasingMode.EaseOut, new CircleEase())));
            EventManager.RegisterClassHandler(typeof(ButtonBase), UIElement.PreviewMouseLeftButtonUpEvent, new MouseButtonEventHandler(
                (s, _) => AnimateScale((UIElement)s, 1.045, 0.28, EasingMode.EaseOut, new BackEase { Amplitude = 0.62 })));
        }

        public static void FadeIn(UIElement target)
        {
            if (!EnterEnabled) return;
            target.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0.45, 1.0, TimeSpan.FromMilliseconds(300))
            {
                EasingFunction = new CircleEase { EasingMode = EasingMode.EaseOut }
            });
        }

        // 图标弹一下：主题切换后的月亮/太阳用回弹缩放，模仿 iOS 控件的反馈
        public static void Pop(FrameworkElement fe)
        {
            if (!SpringEnabled) return;
            var scale = EnsureScale(fe);
            if (scale == null || scale.IsFrozen) return;
            var anim = new DoubleAnimation(0.35, 1.0, TimeSpan.FromMilliseconds(520))
            {
                EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.75 }
            };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, anim);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, anim);
        }

        private static TranslateTransform backdropParallax;
        private static FrameworkElement backdropHost;
        private static double lastParallaxX;
        private static double lastParallaxY;

        // 背景光斑跟随指针轻微视差：手机系统里壁纸随视角偏移的那种感觉。
        // 每次换主题都会重建画刷，所以先摘掉旧处理器，避免越挂越多。
        public static void BindBackdropParallax(FrameworkElement host, TranslateTransform parallax)
        {
            if (backdropHost != null) backdropHost.PreviewMouseMove -= OnBackdropMouseMove;
            backdropHost = host;
            backdropParallax = parallax;
            lastParallaxX = lastParallaxY = 0;
            host.PreviewMouseMove += OnBackdropMouseMove;
        }

        public static void UnbindBackdropParallax()
        {
            if (backdropHost != null) backdropHost.PreviewMouseMove -= OnBackdropMouseMove;
            backdropHost = null;
            backdropParallax = null;
        }

        private static void OnBackdropMouseMove(object sender, MouseEventArgs e)
        {
            if (!BackdropEnabled) return;
            var p = backdropParallax;
            var fe = backdropHost;
            if (p == null || fe == null || p.IsFrozen) return;
            if (fe.ActualWidth < 1 || fe.ActualHeight < 1) return;
            var pos = e.GetPosition(fe);
            double tx = (0.5 - pos.X / fe.ActualWidth) * 0.05;
            double ty = (0.5 - pos.Y / fe.ActualHeight) * 0.04;
            // 位移差太小就不重启动画，否则指针快速移动时动画永远跑不完一段
            if (Math.Abs(tx - lastParallaxX) < 0.004 && Math.Abs(ty - lastParallaxY) < 0.004) return;
            lastParallaxX = tx;
            lastParallaxY = ty;
            GlidTo(p, TranslateTransform.XProperty, tx);
            GlidTo(p, TranslateTransform.YProperty, ty);
        }

        private static void GlidTo(TranslateTransform t, DependencyProperty prop, double to)
        {
            t.BeginAnimation(prop, new DoubleAnimation(to, TimeSpan.FromMilliseconds(650))
            {
                EasingFunction = new CircleEase { EasingMode = EasingMode.EaseOut }
            });
        }

        private static void PlayEnter(FrameworkElement fe)
        {
            // 关掉动效时绝不能先置 Opacity=0：动画不起播的话页面就一直透明了
            if (!EnterEnabled) return;
            var shift = EnsureTranslate(fe);
            if (shift == null) return;
            fe.Opacity = 0;
            fe.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(230))
            {
                EasingFunction = new CircleEase { EasingMode = EasingMode.EaseOut }
            });
            shift.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(18, 0, TimeSpan.FromMilliseconds(340))
            {
                EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.1 }
            });
            var zoom = EnsureScale(fe);
            if (zoom != null && !zoom.IsFrozen)
            {
                var pop = new DoubleAnimation(0.988, 1.0, TimeSpan.FromMilliseconds(380))
                {
                    EasingFunction = new CircleEase { EasingMode = EasingMode.EaseOut }
                };
                zoom.BeginAnimation(ScaleTransform.ScaleXProperty, pop);
                zoom.BeginAnimation(ScaleTransform.ScaleYProperty, pop);
            }
        }

        private static TranslateTransform EnsureTranslate(FrameworkElement fe)
        {
            if (fe.RenderTransform is TranslateTransform tt) return tt;
            if (fe.RenderTransform == null)
            {
                var created = new TranslateTransform();
                fe.RenderTransform = created;
                return created;
            }
            var group = new TransformGroup();
            group.Children.Add(fe.RenderTransform);
            var appended = new TranslateTransform();
            group.Children.Add(appended);
            fe.RenderTransform = group;
            return appended;
        }

        private static void AnimateScale(UIElement e, double to, double seconds, EasingMode mode, EasingFunctionBase ease)
        {
            if (!SpringEnabled) return;
            var scale = EnsureScale(e);
            if (scale == null || scale.IsFrozen) return;
            ease.EasingMode = mode;
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(to, TimeSpan.FromSeconds(seconds)) { EasingFunction = ease });
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(to, TimeSpan.FromSeconds(seconds)) { EasingFunction = ease });
        }

        private static ScaleTransform EnsureScale(UIElement e)
        {
            if (e.GetValue(ScaleOwnerProperty) is ScaleTransform owned) return owned;
            ScaleTransform created;
            switch (e.RenderTransform)
            {
                case null:
                    created = new ScaleTransform(1, 1);
                    e.RenderTransform = created;
                    break;
                case ScaleTransform existing:
                    if (existing.IsFrozen) return null;
                    created = existing;
                    break;
                case TransformGroup group when group.IsFrozen:
                    return null;
                case TransformGroup group:
                    created = new ScaleTransform(1, 1);
                    group.Children.Add(created);
                    break;
                default:
                    // 元素自带旋转/位移等自定义变换，不插手
                    return null;
            }
            e.RenderTransformOrigin = new Point(0.5, 0.5);
            e.SetValue(ScaleOwnerProperty, created);
            return created;
        }

        private static readonly DependencyProperty ShimmerOverlayProperty = DependencyProperty.RegisterAttached(
            "ShimmerOverlay", typeof(Border), typeof(GlassMotion));

        private static readonly DependencyProperty ShimmerSweepProperty = DependencyProperty.RegisterAttached(
            "ShimmerSweep", typeof(TranslateTransform), typeof(GlassMotion));

        private static readonly DependencyProperty ShimmerActiveProperty = DependencyProperty.RegisterAttached(
            "ShimmerActive", typeof(bool), typeof(GlassMotion));

        private static readonly List<WeakReference<FrameworkElement>> breathing = new();
        private static readonly List<WeakReference<Border>> shimmers = new();

        // 进度条流光：不逐个改 25 处 XAML，而是在 ProgressBar 类级别挂处理器，
        // 运行时往模板里 PART_Indicator 所在的面板插一层半透明白带，靠画刷的 RelativeTransform 横扫。
        // 只有真的在推进（0<Value<Maximum 或不确定态）才动，跑满即停——刷机时闪个不停的动效只会干扰读数。
        public static void RegisterGlobalProgressBarMotion()
        {
            EventManager.RegisterClassHandler(typeof(ProgressBar), FrameworkElement.LoadedEvent,
                new RoutedEventHandler((s, _) => UpdateShimmer((ProgressBar)s)));
            EventManager.RegisterClassHandler(typeof(ProgressBar), RangeBase.ValueChangedEvent,
                new RoutedPropertyChangedEventHandler<double>((s, _) => UpdateShimmer((ProgressBar)s)));
            // Loaded 只在建树时发一次，而 IsVisibleChanged 不是路由事件、挂不了类处理器；
            // 条从折叠页里露出来时一定会经历 0→实际尺寸的 SizeChanged，借它补一次判定。
            EventManager.RegisterClassHandler(typeof(ProgressBar), FrameworkElement.SizeChangedEvent,
                new SizeChangedEventHandler((s, e) => UpdateShimmer((ProgressBar)s)));
        }

        private static void UpdateShimmer(ProgressBar bar)
        {
            var overlay = bar.GetValue(ShimmerOverlayProperty) as Border;
            var sweep = bar.GetValue(ShimmerSweepProperty) as TranslateTransform;

            bool running = ShimmerEnabled && bar.IsVisible &&
                (bar.IsIndeterminate || (bar.Value > bar.Minimum && bar.Value < bar.Maximum));
            if (!running)
            {
                if (sweep != null)
                {
                    sweep.BeginAnimation(TranslateTransform.XProperty, null);
                    bar.SetValue(ShimmerActiveProperty, false);
                }
                if (overlay != null) overlay.Opacity = 0;
                return;
            }

            if (overlay == null || sweep == null)
            {
                overlay = CreateShimmerOverlay(bar, out sweep);
                if (overlay == null) return;
                bar.SetValue(ShimmerOverlayProperty, overlay);
                bar.SetValue(ShimmerSweepProperty, sweep);
                shimmers.Add(new WeakReference<Border>(overlay));
            }

            overlay.Opacity = 1;
            // 已经在上游走就不重启动画，否则每次 Value 变化都会把扫光掰回起点
            if ((bool)bar.GetValue(ShimmerActiveProperty)) return;
            bar.SetValue(ShimmerActiveProperty, true);
            sweep.BeginAnimation(TranslateTransform.XProperty,
                new DoubleAnimation(-0.8, 0.8, TimeSpan.FromSeconds(1.6))
                {
                    RepeatBehavior = RepeatBehavior.Forever,
                    EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
                });
        }

        private static Border CreateShimmerOverlay(ProgressBar bar, out TranslateTransform sweep)
        {
            sweep = null;
            if (!(bar.Template?.FindName("PART_Indicator", bar) is FrameworkElement indicator)) return null;
            if (!(System.Windows.Media.VisualTreeHelper.GetParent(indicator) is System.Windows.Controls.Panel host)) return null;

            var band = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0),
                EndPoint = new Point(1, 0),
                MappingMode = BrushMappingMode.RelativeToBoundingBox
            };
            band.GradientStops.Add(new GradientStop(Colors.Transparent, 0));
            band.GradientStops.Add(new GradientStop(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF), 0.5));
            band.GradientStops.Add(new GradientStop(Colors.Transparent, 1));
            sweep = new TranslateTransform();
            band.RelativeTransform = sweep;

            var created = new Border
            {
                Background = band,
                IsHitTestVisible = false,
                CornerRadius = indicator is Border b ? b.CornerRadius : new CornerRadius(0)
            };
            // 插在进度面之后、模板里的百分比文字之前，免得白带糊在数字上
            host.Children.Insert(host.Children.IndexOf(indicator) + 1, created);
            return created;
        }

        // 状态灯呼吸：只在"正在检测"这类过程态下常驻播，断开时保持静止。
        public static void SetBreathe(FrameworkElement fe, bool on)
        {
            if (fe == null) return;
            if (!on || !BreatheEnabled)
            {
                fe.BeginAnimation(UIElement.OpacityProperty, null);
                var rest = fe.GetValue(ScaleOwnerProperty) as ScaleTransform;
                rest?.BeginAnimation(ScaleTransform.ScaleXProperty, null);
                rest?.BeginAnimation(ScaleTransform.ScaleYProperty, null);
                return;
            }

            var pulse = new DoubleAnimation(1.0, 0.42, TimeSpan.FromMilliseconds(1100))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
            };
            fe.BeginAnimation(UIElement.OpacityProperty, pulse);
            breathing.Add(new WeakReference<FrameworkElement>(fe));
        }

        // 刚连上设备时脉冲两下就停：设备一旦插上就是长期在线，常驻呼吸会变成干扰读数的闪灯。
        public static void Pulse(FrameworkElement fe, int cycles = 2)
        {
            if (fe == null || !BreatheEnabled) return;
            var frames = new DoubleAnimationUsingKeyFrames();
            // KeyTime 是绝对时间，两下就得一路往后排，不能每轮都从 420ms 开始
            var step = TimeSpan.FromMilliseconds(420);
            for (var i = 0; i < cycles; i++)
            {
                frames.KeyFrames.Add(new EasingDoubleKeyFrame(0.35, KeyTime.FromTimeSpan(step * (i * 2 + 1)))
                {
                    EasingFunction = new CircleEase { EasingMode = EasingMode.EaseOut }
                });
                frames.KeyFrames.Add(new EasingDoubleKeyFrame(1.0, KeyTime.FromTimeSpan(step * (i * 2 + 2)))
                {
                    EasingFunction = new CircleEase { EasingMode = EasingMode.EaseIn }
                });
            }
            fe.BeginAnimation(UIElement.OpacityProperty, frames);
        }

        // 关掉动效时把常驻动画显式停掉：一次性动画会自己跑完，Forever 的不会。
        public static void StopContinuousMotion()
        {
            foreach (var reference in breathing)
            {
                if (reference.TryGetTarget(out var fe)) fe.BeginAnimation(UIElement.OpacityProperty, null);
            }
            breathing.Clear();

            foreach (var reference in shimmers)
            {
                if (!reference.TryGetTarget(out var overlay)) continue;
                overlay.Opacity = 0;
                if (overlay.Background is LinearGradientBrush band && band.RelativeTransform is TranslateTransform sweep)
                    sweep.BeginAnimation(TranslateTransform.XProperty, null);
            }
            shimmers.Clear();
        }
    }
}
