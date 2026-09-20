using System.Text;
using System.Windows;

namespace WpfApp1
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : System.Windows.Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
            // base.OnStartup 会按 StartupUri 造主窗口，所以主题字典必须在这之前换好。
            // 必须写全限定名：Application.MainWindow 这个实例属性会把裸 MainWindow 遮掉。
            GlassSettings.Current.ApplyToMotion();
            WpfApp1.MainWindow.ApplyThemeDictionary(GlassSettings.Current);
            base.OnStartup(e);
        }
    }
}
