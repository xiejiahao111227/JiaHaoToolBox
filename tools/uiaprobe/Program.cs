using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;

// 嘉豪工具箱的 UI 巡检驱动。本机 PowerShell 5.1 把脚本送进 AMSI 扫描时会随机段错误
// （AmsiUtils.AmsiScanBuffer AccessViolation），巡检脚本跑不动，所以改成这个自编译的小工具：
// 同样走 Win32 + UIA，但没有「脚本内容被安全软件扫描」这一步。
//
// 用法：uiaprobe <命令> [参数]
//   run <exe> [参数...]            启动并等主窗口出现，打印 PID/HWND/样式位
//   shot <hwnd> <png>              PrintWindow 抓窗口（WPF 分层窗口也抓得到）
//   tree <pid> [上限]              打印该进程所有顶层窗口及控件（类型/自动化Id/名称/矩形）
//   find <pid> id|name <值>        找控件，打印中心坐标
//   invoke <pid> <名称>            按名称执行 InvokePattern / SelectionItem（原生对话框按钮够用）
//   click <hwnd> <x> <y> [等待毫秒] 抢前台后投真实硬件点击（WPF 只认这个）
//   style <hwnd>                   打印样式位（WS_EX_LAYERED / WS_THICKFRAME 是结论所在）
//   wait-exit <pid>                等进程退掉
//   kill <pid>                     收尾
namespace UiaProbe
{
    internal static class Program
    {
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr SetActiveWindow(IntPtr h);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint a, uint b, bool join);
        [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, IntPtr extra);
        [DllImport("user32.dll")] private static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr h, int index);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();

        private const int GWL_STYLE = -16;
        private const int GWL_EXSTYLE = -20;
        private const long WS_THICKFRAME = 0x00040000;
        private const long WS_CAPTION = 0x00C00000;
        private const long WS_MINIMIZEBOX = 0x00020000;
        private const long WS_EX_LAYERED = 0x00080000;
        private const uint PW_RENDERFULLCONTENT = 2;

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }

        [STAThread]
        private static int Main(string[] argv)
        {
            Console.OutputEncoding = Encoding.UTF8;
            if (argv.Length == 0) { Say("用法: uiaprobe <run|shot|tree|find|invoke|click|style|wait-exit|kill> ..."); return 2; }
            try
            {
                switch (argv[0])
                {
                    case "run": return Run(argv);
                    case "shot": return Shot(argv);
                    case "tree": return Tree(argv);
                    case "find": return Find(argv);
                    case "invoke": return Invoke(argv);
                    case "click": return Click(argv);
                    case "style": return Style(argv);
                    case "wait-exit": return WaitExit(argv);
                    case "kill": return Kill(argv);
                    default: Say("未知命令 " + argv[0]); return 2;
                }
            }
            catch (Exception ex)
            {
                Say("ERROR " + ex.GetType().Name + " " + ex.Message);
                return 1;
            }
        }

        private static void Say(string s) => Console.Out.WriteLine(s);

        private static IntPtr H(string s)
        {
            s = s.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? s.Substring(2) : s;
            return new IntPtr(long.Parse(s, System.Globalization.NumberStyles.AllowHexSpecifier));
        }

        private static string Hex(IntPtr h) => "0x" + h.ToInt64().ToString("X");

        private static string StyleLine(IntPtr h)
        {
            if (h == IntPtr.Zero) return "no-window";
            long style = GetWindowLongPtr(h, GWL_STYLE).ToInt64();
            long ex = GetWindowLongPtr(h, GWL_EXSTYLE).ToInt64();
            string bits = (style & WS_THICKFRAME) != 0 ? "THICKFRAME " : "!THICKFRAME ";
            bits += (style & WS_CAPTION) != 0 ? "CAPTION " : "!CAPTION ";
            bits += (style & WS_MINIMIZEBOX) != 0 ? "MINBOX " : "!MINBOX ";
            bits += (ex & WS_EX_LAYERED) != 0 ? "LAYERED" : "!LAYERED";
            return string.Format("style=0x{0:X8} exstyle=0x{1:X8} [{2}]", style, ex, bits);
        }

        private static int Style(string[] a) { Say(StyleLine(H(a[1]))); return 0; }

        private static AutomationElement[] WindowsOf(int pid)
        {
            var cond = new PropertyCondition(AutomationElement.ProcessIdProperty, pid);
            var kids = AutomationElement.RootElement.FindAll(TreeScope.Children, cond);
            var arr = new AutomationElement[kids.Count];
            for (int i = 0; i < kids.Count; i++) arr[i] = kids[i];
            return arr;
        }

        private static int Run(string[] a)
        {
            var psi = new ProcessStartInfo(a[1]) { UseShellExecute = false };
            for (int i = 2; i < a.Length; i++) psi.ArgumentList.Add(a[i]);
            var p = Process.Start(psi);
            var deadline = DateTime.Now.AddSeconds(60);
            while (DateTime.Now < deadline)
            {
                Thread.Sleep(500);
                p.Refresh();
                if (p.HasExited) { Say("EXITED-EARLY code=" + p.ExitCode); return 1; }
                IntPtr hwnd = p.MainWindowHandle;
                if (hwnd != IntPtr.Zero)
                {
                    var r = default(RECT);
                    if (GetWindowRect(hwnd, out r) && r.Right - r.Left >= 100)
                    {
                        Say(string.Format("PID={0} HWND={1} RECT={2}x{3} {4}",
                            p.Id, Hex(hwnd), r.Right - r.Left, r.Bottom - r.Top, StyleLine(hwnd)));
                        return 0;
                    }
                }
            }
            Say("NO-WINDOW pid=" + p.Id);
            return 1;
        }

        private static int Shot(string[] a)
        {
            IntPtr h = H(a[1]);
            var r = default(RECT);
            for (int i = 0; i < 12; i++)
            {
                ShowWindow(h, 9);
                SetForegroundWindow(h);
                Thread.Sleep(400);
                if (!GetWindowRect(h, out r)) { Say("NO-RECT"); return 1; }
                if (r.Right - r.Left >= 60 && r.Bottom - r.Top >= 40) break;
            }
            int w = r.Right - r.Left, hh = r.Bottom - r.Top;
            if (w < 60 || hh < 40) { Say("BAD-RECT " + w + "x" + hh); return 1; }
            using (var bmp = new Bitmap(w, hh))
            using (var g = Graphics.FromImage(bmp))
            {
                IntPtr hdc = g.GetHdc();
                PrintWindow(h, hdc, PW_RENDERFULLCONTENT);
                g.ReleaseHdc(hdc);
                bmp.Save(a[2], ImageFormat.Png);
            }
            Say("shot " + a[2] + " (" + w + "x" + hh + ")");
            return 0;
        }

        private static int Tree(string[] a)
        {
            int pid = int.Parse(a[1]);
            int max = a.Length > 2 ? int.Parse(a[2]) : 400;
            var kids = WindowsOf(pid);
            if (kids.Length == 0) { Say("NO-WINDOW pid=" + pid); return 1; }
            for (int i = 0; i < kids.Length; i++)
            {
                var c = kids[i].Current;
                var r = c.BoundingRectangle;
                Say(string.Format("WINDOW class={0} name={1} hwnd={2} rect={3},{4} {5}x{6}",
                    c.ClassName, c.Name, Hex(new IntPtr(c.NativeWindowHandle)),
                    (int)r.X, (int)r.Y, (int)r.Width, (int)r.Height));
                var all = kids[i].FindAll(TreeScope.Descendants, Condition.TrueCondition);
                Say("  后代 " + all.Count);
                for (int k = 0; k < Math.Min(all.Count, max); k++)
                {
                    var e = all[k].Current;
                    if (string.IsNullOrEmpty(e.Name) && string.IsNullOrEmpty(e.AutomationId)) continue;
                    Say(string.Format("  {0} id={1} name={2} xywh={3},{4},{5}x{6} off={7} en={8}",
                        e.ControlType.ProgrammaticName.Replace("ControlType.", ""), e.AutomationId, e.Name,
                        (int)e.BoundingRectangle.X, (int)e.BoundingRectangle.Y,
                        (int)e.BoundingRectangle.Width, (int)e.BoundingRectangle.Height,
                        e.IsOffscreen, e.IsEnabled));
                }
            }
            return 0;
        }

        // 对话框（#32770）和主窗口是两个顶层窗口，所以遍历该进程名下所有窗口，别只看第一个
        private static AutomationElement Match(int pid, string by, string value)
        {
            var prop = by == "id" ? AutomationElement.AutomationIdProperty : AutomationElement.NameProperty;
            var kids = WindowsOf(pid);
            AutomationElement fallback = null;
            for (int i = 0; i < kids.Length; i++)
            {
                var all = kids[i].FindAll(TreeScope.Descendants, new PropertyCondition(prop, value));
                for (int k = 0; k < all.Count; k++)
                {
                    if (!all[k].Current.IsOffscreen) return all[k];
                    if (fallback == null) fallback = all[k];
                }
            }
            return fallback;
        }

        private static int Find(string[] a)
        {
            var el = Match(int.Parse(a[1]), a[2], a[3]);
            if (el == null) { Say("MISS " + a[3]); return 1; }
            var r = el.Current.BoundingRectangle;
            Say(string.Format("FOUND hwnd={0} cx={1} cy={2} enabled={3} rect={4},{5} {6}x{7}",
                Hex(new IntPtr(el.Current.NativeWindowHandle)), (int)(r.Left + r.Width / 2), (int)(r.Top + r.Height / 2),
                el.Current.IsEnabled, (int)r.X, (int)r.Y, (int)r.Width, (int)r.Height));
            return 0;
        }

        private static int Invoke(string[] a)
        {
            var el = Match(int.Parse(a[1]), "name", a[2]);
            if (el == null) { Say("MISS " + a[2]); return 1; }
            object pat;
            if (el.TryGetCurrentPattern(InvokePattern.Pattern, out pat))
            {
                ((InvokePattern)pat).Invoke();
                Say("INVOKED " + a[2]);
                return 0;
            }
            // RadioButton / 列表项给的是 SelectionItemPattern 而不是 InvokePattern
            if (el.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pat))
            {
                ((SelectionItemPattern)pat).Select();
                Say("SELECTED " + a[2]);
                return 0;
            }
            Say("NO-PATTERN " + a[2]);
            return 1;
        }

        private static void ForceForeground(IntPtr hwnd)
        {
            uint fgPid;
            IntPtr fg = GetForegroundWindow();
            uint fgTid = GetWindowThreadProcessId(fg, out fgPid);
            uint curTid = GetCurrentThreadId();
            bool attached = fgPid != 0 && fgTid != 0 && fgTid != curTid;
            if (attached) AttachThreadInput(curTid, fgTid, true);
            keybd_event(0x12, 0, 0, IntPtr.Zero);
            keybd_event(0x12, 0, 2, IntPtr.Zero);
            if (hwnd != IntPtr.Zero)
            {
                ShowWindow(hwnd, 5);
                BringWindowToTop(hwnd);
                SetForegroundWindow(hwnd);
                SetActiveWindow(hwnd);
            }
            if (attached) AttachThreadInput(curTid, fgTid, false);
            Thread.Sleep(250);
        }

        private static int Click(string[] a)
        {
            IntPtr hwnd = H(a[1]);
            int x = int.Parse(a[2]), y = int.Parse(a[3]);
            int wait = a.Length > 4 ? int.Parse(a[4]) : 1200;
            ForceForeground(hwnd);
            SetCursorPos(x, y);
            Thread.Sleep(220);
            mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
            Thread.Sleep(90);
            mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
            Thread.Sleep(wait);
            Say(string.Format("clicked {0},{1}", x, y));
            return 0;
        }

        private static int WaitExit(string[] a)
        {
            int pid = int.Parse(a[1]);
            var deadline = DateTime.Now.AddSeconds(30);
            while (DateTime.Now < deadline)
            {
                try { var p = Process.GetProcessById(pid); p.WaitForExit(300); if (p.HasExited) { Say("EXITED " + pid); return 0; } }
                catch (ArgumentException) { Say("EXITED " + pid); return 0; }
                Thread.Sleep(300);
            }
            Say("STILL-ALIVE " + pid);
            return 1;
        }

        private static int Kill(string[] a)
        {
            int pid = int.Parse(a[1]);
            try { var p = Process.GetProcessById(pid); p.Kill(); Say("killed " + pid); }
            catch (ArgumentException) { Say("已经没了 " + pid); }
            return 0;
        }
    }
}
