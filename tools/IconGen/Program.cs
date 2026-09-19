using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Markup;
using System.Windows.Media;
using SharpVectors.Converters;
using SharpVectors.Renderers.Wpf;

// 把 images\*.svg 预转换成冻结的 DrawingImage 资源字典 Icons.xaml。
// 运行时每个 SvgViewbox 实例都要重新解析 SVG 并重建绘图对象（121 个实例约 1.9 秒，
// 全部压在窗口构造之前的 InitializeComponent 里）；预转换后运行时只剩查表 + 绘图。
class Program
{
    static readonly Regex DrawableElement = new Regex("<(path|circle|rect|g|polygon|polyline|ellipse|line|use)\\b", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    static readonly Regex DataImage = new Regex("<image[^>]*?xlink:href=\"data:image/(png|jpeg|jpg);base64,([^\"]+)\"[^>]*?/>", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    static readonly Regex Num = new Regex(@"-?\d*\.?\d+");

    static int Main(string[] args)
    {
        string projectDir = args.Length > 0 ? args[0] : @"E:\114514\JiaHaoToolBox\JiaHaoToolBox";
        string imagesDir = Path.Combine(projectDir, "images");
        string outFile = Path.Combine(projectDir, "Icons.xaml");

        var sb = new StringBuilder();
        sb.AppendLine("<ResourceDictionary xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"");
        sb.AppendLine("                    xmlns:x=\"http://schemas.microsoft.com/winfx/2006/xaml\">");

        var manifest = new StringBuilder();
        int ok = 0, raster = 0, fail = 0;

        foreach (var file in Directory.GetFiles(imagesDir, "*.svg").OrderBy(f => f, StringComparer.OrdinalIgnoreCase))
        {
            string name = Path.GetFileNameWithoutExtension(file);
            string key = "ic_" + Regex.Replace(name, "[^A-Za-z0-9_]", "_");
            string text = File.ReadAllText(file);

            try
            {
                if (!DrawableElement.IsMatch(text))
                {
                    var m = DataImage.Match(text);
                    if (!m.Success || m.Groups[1].Value.ToLower() != "png")
                        throw new InvalidOperationException("没有可转换的矢量内容");
                    string png = Path.Combine(imagesDir, name + ".png");
                    File.WriteAllBytes(png, Convert.FromBase64String(m.Groups[2].Value.Trim()));
                    sb.AppendLine("    <!-- " + name + ".svg 内嵌位图 -->");
                    sb.AppendLine("    <BitmapImage x:Key=\"" + key + "\" UriSource=\"images/" + name + ".png\" CacheOption=\"OnLoad\" />");
                    manifest.AppendLine("RASTER\t" + name + "\t" + key);
                    raster++;
                    continue;
                }

                var settings = new WpfDrawingSettings { IncludeRuntime = false };
                using var reader = new FileSvgReader(settings);
                DrawingGroup dg = reader.Read(file);
                if (dg == null)
                    throw new InvalidOperationException("reader produced no drawing");

                var image = new DrawingImage { Drawing = dg };
                if (!image.IsFrozen && image.CanFreeze) image.Freeze();

                string xaml = XamlWriter.Save(image);
                int gt = xaml.IndexOf('>');
                string open = Regex.Replace(xaml.Substring(0, gt), "\\s*xmlns(:[A-Za-z0-9_]+)?=\"[^\"]*\"", "");
                open = Regex.Replace(open, "\\s*xml:space=\"[^\"]*\"", "");
                open = open.Replace("<DrawingImage", "<DrawingImage x:Key=\"" + key + "\"");
                string body = xaml.Substring(gt);
                body = Num.Replace(body, m => m.Value.Contains(".")
                    ? Math.Round(decimal.Parse(m.Value, System.Globalization.CultureInfo.InvariantCulture), 2, System.MidpointRounding.AwayFromZero).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)
                    : m.Value);

                sb.AppendLine("    <!-- " + name + ".svg -->");
                sb.AppendLine("    " + open + body);
                manifest.AppendLine("OK\t" + name + "\t" + key);
                ok++;
            }
            catch (Exception ex)
            {
                manifest.AppendLine("FAIL\t" + name + "\t" + ex.GetType().Name + ": " + ex.Message);
                fail++;
            }
        }

        sb.AppendLine("</ResourceDictionary>");
        File.WriteAllText(outFile, sb.ToString(), new UTF8Encoding(true));
        File.WriteAllText(Path.GetFullPath(Path.Combine(projectDir, "..", "tools", "icon-manifest.tsv")),
            manifest.ToString(), new UTF8Encoding(false));
        Console.WriteLine($"vector={ok} raster={raster} fail={fail} -> {outFile} ({new FileInfo(outFile).Length} bytes)");
        return fail == 0 ? 0 : 1;
    }
}
