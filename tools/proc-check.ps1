# proc-check: 报告工具箱与刷写相关外部工具是否在运行（ps-enc 会丢掉第一行，这里放注释）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
foreach ($n in 'JiaHaoToolBox','adb','fastboot','scrcpy','7z','aria2c','fh_loader','QSaharaServer') {
    $ps = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
    if ($ps.Count -eq 0) { Write-Output ("{0,-16} : 0" -f $n); continue }
    foreach ($p in $ps) {
        Write-Output ("{0,-16} PID={1} 窗口='{2}' 响应={3} 启动={4}" -f $n, $p.Id, $p.MainWindowTitle, $p.Responding, $p.StartTime)
    }
}
