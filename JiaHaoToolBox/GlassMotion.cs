using System;
using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ButtonBase = System.Windows.Controls.Primitives.ButtonBase;
using MouseEventHandler = System.Windows.Input.MouseEventHandler;
using MouseButtonEventHandler = System.Windows.Input.MouseButtonEventHandler;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using Point = System.Windows.Point;

namespace WpfApp1
{
    // 液态玻璃动效：悬停/按下的弹性缩放、页面淡入上滑、主题切换淡入。
    // 全部走 RenderTransform + Storyboard（GPU 合成层），不引入运行时模糊，启动耗时不受影响。
    public static class GlassMotion
    {
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
            target.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0.45, 1.0, TimeSpan.FromMilliseconds(300))
            {
                EasingFunction = new CircleEase { EasingMode = EasingMode.EaseOut }
            });
        }

        // 图标弹一下：主题切换后的月亮/太阳用回弹缩放，模仿 iOS 控件的反馈
        public static void Pop(FrameworkElement fe)
        {
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

        private static void OnBackdropMouseMove(object sender, MouseEventArgs e)
        {
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
    }
}
