using System;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using Ellipse = System.Windows.Shapes.Ellipse;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;

// 预渲染液态玻璃的彩色光斑背景：高斯模糊的径向渐变椭圆叠在不透明底色上。
// 做成构建期图片而不是运行时 BlurEffect，是为了不给窗口显示路径加任何逐帧重绘开销。
// 用法：dotnet run --project tools/GlassGen -c Release -- "<工程目录>"
internal static class Program
{
    private const double Width = 1000;
    private const double Height = 800;
    private const double Blur = 72;

    private readonly record struct Blob(double X, double Y, double Rx, double Ry, double Angle, uint Rgb, double Alpha);

    private static readonly (string Name, uint Base, Blob[] Blobs)[] Themes =
    {
        ("glass-light", 0xFFF3F7FD, new[]
        {
            new Blob(150, 90, 300, 240, -18, 0xFF8CC8FF, 1.0),
            new Blob(880, 150, 260, 300, 24, 0xFFA9B6FF, 1.0),
            new Blob(720, 700, 340, 250, -12, 0xFF7FD8F5, 1.0),
            new Blob(120, 720, 250, 210, 30, 0xFFB9EFDF, 0.9),
            new Blob(470, 380, 220, 180, 0, 0xFFFFFFFF, 0.85),
            new Blob(560, 60, 200, 120, 15, 0xFFC9E4FF, 0.9),
        }),
        ("glass-dark", 0xFF0D1420, new[]
        {
            new Blob(150, 90, 300, 240, -18, 0xFF1E5C96, 1.0),
            new Blob(880, 150, 260, 300, 24, 0xFF2A3A78, 1.0),
            new Blob(720, 700, 340, 250, -12, 0xFF12617F, 1.0),
            new Blob(120, 720, 250, 210, 30, 0xFF14514A, 0.9),
            new Blob(470, 380, 220, 180, 0, 0xFF2E7CD6, 0.7),
            new Blob(560, 60, 200, 120, 15, 0xFF1A3E6B, 0.9),
        }),
    };

    private static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("用法: GlassGen <工程目录>");
            return 1;
        }

        string imageDir = Path.Combine(args[0], "images");
        Directory.CreateDirectory(imageDir);

        int exit = 0;
        foreach (var theme in Themes)
        {
            string target = Path.Combine(imageDir, theme.Name + ".png");
            Exception failure = null;
            var worker = new Thread(() =>
            {
                try
                {
                    WritePng(target, theme.Base, theme.Blobs);
                }
                catch (Exception ex)
                {
                    failure = ex;
                }
            });
            worker.SetApartmentState(ApartmentState.STA);
            worker.Start();
            worker.Join();

            if (failure != null)
            {
                Console.Error.WriteLine($"{theme.Name} 生成失败: {failure.Message}");
                exit = 1;
                continue;
            }
            Console.WriteLine($"{target} ({new FileInfo(target).Length / 1024} KB)");
        }
        return exit;
    }

    private static void WritePng(string path, uint baseColor, Blob[] blobs)
    {
        var canvas = new Canvas { Width = Width, Height = Height, Background = Brushes.Transparent };
        foreach (Blob blob in blobs)
        {
            // Blob.Rgb 按 0xAARRGGBB 书写，透明度另由 Alpha 控制
            Color color = Color.FromArgb((byte)0xFF, (byte)(blob.Rgb >> 16), (byte)(blob.Rgb >> 8), (byte)blob.Rgb);
            var brush = new RadialGradientBrush
            {
                GradientOrigin = new Point(0.5, 0.5),
                Center = new Point(0.5, 0.5),
                RadiusX = 0.5,
                RadiusY = 0.5,
            };
            brush.GradientStops.Add(new GradientStop(WithAlpha(color, blob.Alpha), 0));
            brush.GradientStops.Add(new GradientStop(WithAlpha(color, blob.Alpha * 0.72), 0.45));
            brush.GradientStops.Add(new GradientStop(WithAlpha(color, 0), 1));
            brush.Freeze();

            var ellipse = new Ellipse
            {
                Width = blob.Rx * 2,
                Height = blob.Ry * 2,
                Fill = brush,
                RenderTransformOrigin = new Point(0.5, 0.5),
                RenderTransform = new RotateTransform(blob.Angle),
            };
            Canvas.SetLeft(ellipse, blob.X - blob.Rx);
            Canvas.SetTop(ellipse, blob.Y - blob.Ry);
            canvas.Children.Add(ellipse);
        }

        canvas.Effect = new BlurEffect { Radius = Blur, KernelType = KernelType.Gaussian };
        var size = new Size(Width, Height);
        canvas.Measure(size);
        canvas.Arrange(new Rect(size));

        var blurred = new RenderTargetBitmap((int)Width, (int)Height, 96, 96, PixelFormats.Pbgra32);
        blurred.Render(canvas);
        blurred.Freeze();

        var composited = new DrawingVisual();
        using (DrawingContext dc = composited.RenderOpen())
        {
            dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(
                (byte)(baseColor >> 24), (byte)(baseColor >> 16), (byte)(baseColor >> 8), (byte)baseColor)), null, new Rect(0, 0, Width, Height));
            dc.DrawImage(blurred, new Rect(0, 0, Width, Height));
        }

        var output = new RenderTargetBitmap((int)Width, (int)Height, 96, 96, PixelFormats.Pbgra32);
        output.Render(composited);
        output.Freeze();

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(output));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }

    private static Color WithAlpha(Color color, double alpha) => Color.FromArgb((byte)(Math.Clamp(alpha, 0, 1) * 255), color.R, color.G, color.B);
}
