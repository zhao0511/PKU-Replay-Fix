@echo off
setlocal
set "PKU_SELF=%~f0"
set "PKU_TARGET=%~dp0"
set "PKU_TEMP=%TEMP%\PKU-Art-TS-to-MP4-%RANDOM%-%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText($env:PKU_SELF);$m='###__POWERSHELL_BELOW__###';$i=$c.LastIndexOf($m);if($i -lt 0){exit 2};$s=$c.Substring($i+$m.Length) -replace '^\r?\n','';[IO.File]::WriteAllText($env:PKU_TEMP,$s,(New-Object Text.UTF8Encoding($true)))"
if errorlevel 1 (
    echo.
    echo Failed to prepare the embedded PowerShell program.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%PKU_TEMP%"
set "PKU_RC=%ERRORLEVEL%"
del /q "%PKU_TEMP%" >nul 2>&1

if not "%PKU_RC%"=="0" (
    echo.
    echo The program ended with error code %PKU_RC%.
    echo.
    pause
)

exit /b %PKU_RC%
###__POWERSHELL_BELOW__###
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$TargetDir = $env:PKU_TARGET
if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    $TargetDir = (Get-Location).Path
}
$TargetDir = $TargetDir.Trim().Trim('"')
try {
    $TargetDir = [System.IO.Path]::GetFullPath($TargetDir)
} catch {
    $TargetDir = (Get-Location).Path
}

$script:CancelRequested = $false
$script:CurrentProcess = $null
$script:IsRunning = $false
$script:FfmpegPath = $null
$script:FfprobePath = $null

function Resolve-Executable {
    param([Parameter(Mandatory=$true)][string]$Name)

    $cmd = Get-Command ($Name + ".exe") -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        return $cmd.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA ("Microsoft\WinGet\Links\" + $Name + ".exe")),
        (Join-Path $env:LOCALAPPDATA ("Microsoft\WindowsApps\" + $Name + ".exe"))
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Refresh-ProcessPath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = (($machine, $user) | Where-Object { $_ }) -join ";"
}

function Add-Log {
    param([string]$Text)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$timestamp] $Text`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-ProgressSafe {
    param(
        [System.Windows.Forms.ProgressBar]$Bar,
        [double]$Percent
    )
    $value = [int][Math]::Round([Math]::Max(0, [Math]::Min(100, $Percent)))
    $Bar.Value = $value
}

function Get-MediaDuration {
    param([string]$Path)
    try {
        $out = & $script:FfprobePath -v error -show_entries format=duration -of "default=noprint_wrappers=1:nokey=1" "$Path" 2>$null
        $value = 0.0
        $first = $out | Select-Object -First 1
        if ([double]::TryParse(
            $first,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value
        )) {
            return $value
        }
    } catch {}
    return 0.0
}

function Get-CodecSummary {
    param([string]$Path)
    try {
        $rows = & $script:FfprobePath -v error -select_streams "v:a" -show_entries stream=codec_type,codec_name -of "csv=p=0" "$Path" 2>$null
        if ($rows) {
            return (($rows | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join " / ")
        }
    } catch {}
    return ""
}

function Test-Mp4 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        if ((Get-Item -LiteralPath $Path).Length -le 0) { return $false }
        return ((Get-MediaDuration -Path $Path) -gt 0)
    } catch {
        return $false
    }
}

function Ensure-FFmpeg {
    Refresh-ProcessPath
    $script:FfmpegPath = Resolve-Executable "ffmpeg"
    $script:FfprobePath = Resolve-Executable "ffprobe"

    if ($script:FfmpegPath -and $script:FfprobePath) {
        Add-Log "FFmpeg / ffprobe 已就绪。"
        return $true
    }

    Add-Log "未检测到 FFmpeg / ffprobe。"

    $answer = [System.Windows.Forms.MessageBox]::Show(
        "未检测到 FFmpeg。`r`n`r`n本程序需要 FFmpeg 才能无损封装 TS → MP4。是否现在自动安装？`r`n`r`n将通过 Windows Package Manager (winget) 安装 Gyan.FFmpeg。",
        "需要安装 FFmpeg",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        Add-Log "用户取消了 FFmpeg 自动安装。"
        return $false
    }

    $winget = Resolve-Executable "winget"
    if (-not $winget) {
        Add-Log "错误：系统没有找到 winget。"
        [System.Windows.Forms.MessageBox]::Show(
            "系统没有找到 winget，因此无法自动安装 FFmpeg。`r`n`r`n请安装/启用 Microsoft 的【应用安装程序 (App Installer) / Windows Package Manager】，或手动安装 FFmpeg 后再运行本程序。",
            "无法自动安装",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }

    $currentLabel.Text = "正在安装 FFmpeg，请稍候…"
    $overallLabel.Text = "正在准备运行环境"
    $currentProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $currentProgress.MarqueeAnimationSpeed = 25
    Add-Log "正在通过 winget 安装 Gyan.FFmpeg…"
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $args = @(
            "install",
            "--id", "Gyan.FFmpeg",
            "-e",
            "--source", "winget",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--silent"
        )

        $p = Start-Process -FilePath $winget -ArgumentList $args -PassThru -WindowStyle Hidden

        while (-not $p.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 120
        }

        Add-Log ("winget 安装进程结束，退出码：{0}" -f $p.ExitCode)
    }
    catch {
        Add-Log "自动安装失败：$($_.Exception.Message)"
    }
    finally {
        $currentProgress.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $currentProgress.MarqueeAnimationSpeed = 0
        Set-ProgressSafe $currentProgress 0
    }

    Refresh-ProcessPath
    Start-Sleep -Milliseconds 400
    $script:FfmpegPath = Resolve-Executable "ffmpeg"
    $script:FfprobePath = Resolve-Executable "ffprobe"

    if ($script:FfmpegPath -and $script:FfprobePath) {
        Add-Log "FFmpeg 安装成功，继续处理。"
        return $true
    }

    Add-Log "安装后仍未找到 FFmpeg / ffprobe。"
    [System.Windows.Forms.MessageBox]::Show(
        "自动安装没有成功，或者系统尚未刷新命令路径。`r`n`r`n请尝试重新运行本程序；如果仍然失败，请手动安装 FFmpeg。",
        "FFmpeg 尚不可用",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return $false
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "PKU-Art TS → MP4 一键修复 v2"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(780, 590)
$form.MinimumSize = New-Object System.Drawing.Size(780, 590)
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.BackColor = [System.Drawing.Color]::White

$title = New-Object System.Windows.Forms.Label
$title.Text = "PKU-Art 已下载录播一键转换 / 修复"
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 15, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($title)

$desc = New-Object System.Windows.Forms.Label
$desc.Text = "当前文件夹中的所有 .ts 都会尝试无损封装为 .mp4；成功验证后才删除原 .ts。"
$desc.AutoSize = $true
$desc.Location = New-Object System.Drawing.Point(22, 55)
$form.Controls.Add($desc)

$compat = New-Object System.Windows.Forms.Label
$compat.Text = "适用于教学网常见 H.264 + AAC TS；其他格式若无法无损封装会保留原文件。"
$compat.AutoSize = $true
$compat.Location = New-Object System.Drawing.Point(22, 79)
$form.Controls.Add($compat)

$dirLabel = New-Object System.Windows.Forms.Label
$dirLabel.Text = "文件夹：$TargetDir"
$dirLabel.AutoEllipsis = $true
$dirLabel.Location = New-Object System.Drawing.Point(22, 108)
$dirLabel.Size = New-Object System.Drawing.Size(720, 20)
$form.Controls.Add($dirLabel)

$currentLabel = New-Object System.Windows.Forms.Label
$currentLabel.Text = "准备中…"
$currentLabel.AutoEllipsis = $true
$currentLabel.Location = New-Object System.Drawing.Point(22, 143)
$currentLabel.Size = New-Object System.Drawing.Size(720, 22)
$form.Controls.Add($currentLabel)

$currentProgress = New-Object System.Windows.Forms.ProgressBar
$currentProgress.Location = New-Object System.Drawing.Point(22, 170)
$currentProgress.Size = New-Object System.Drawing.Size(720, 24)
$currentProgress.Minimum = 0
$currentProgress.Maximum = 100
$form.Controls.Add($currentProgress)

$overallLabel = New-Object System.Windows.Forms.Label
$overallLabel.Text = "总体进度：0%"
$overallLabel.Location = New-Object System.Drawing.Point(22, 207)
$overallLabel.Size = New-Object System.Drawing.Size(720, 22)
$form.Controls.Add($overallLabel)

$overallProgress = New-Object System.Windows.Forms.ProgressBar
$overallProgress.Location = New-Object System.Drawing.Point(22, 233)
$overallProgress.Size = New-Object System.Drawing.Size(720, 24)
$overallProgress.Minimum = 0
$overallProgress.Maximum = 100
$form.Controls.Add($overallProgress)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(22, 275)
$logBox.Size = New-Object System.Drawing.Size(720, 205)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(248,248,248)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($logBox)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = "取消"
$cancelButton.Location = New-Object System.Drawing.Point(552, 497)
$cancelButton.Size = New-Object System.Drawing.Size(90, 32)
$cancelButton.Add_Click({
    if ($script:IsRunning) {
        $script:CancelRequested = $true
        Add-Log "正在取消…当前 TS 会保留。"
        try {
            if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
                $script:CurrentProcess.Kill()
            }
        } catch {}
    }
})
$form.Controls.Add($cancelButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "关闭"
$closeButton.Enabled = $false
$closeButton.Location = New-Object System.Drawing.Point(652, 497)
$closeButton.Size = New-Object System.Drawing.Size(90, 32)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:IsRunning) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "转换仍在进行。确定要取消并关闭吗？`r`n当前正在处理的 TS 不会被删除。",
            "确认关闭",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
            return
        }
        $script:CancelRequested = $true
        try {
            if ($script:CurrentProcess -and -not $script:CurrentProcess.HasExited) {
                $script:CurrentProcess.Kill()
            }
        } catch {}
    }
})

$form.Add_Shown({
    $script:IsRunning = $true
    $closeButton.Enabled = $false

    try {
        if (-not (Ensure-FFmpeg)) {
            $currentLabel.Text = "缺少 FFmpeg，未开始转换。"
            return
        }

        $files = @(Get-ChildItem -LiteralPath $TargetDir -Filter "*.ts" -File | Sort-Object Name)

        if ($files.Count -eq 0) {
            Add-Log "当前文件夹没有找到 .ts 文件。"
            $currentLabel.Text = "没有需要处理的文件。"
            return
        }

        Add-Log ("找到 {0} 个 TS 文件。" -f $files.Count)

        $success = 0
        $failed = 0
        $skipped = 0

        for ($i = 0; $i -lt $files.Count; $i++) {
            if ($script:CancelRequested) { break }

            $src = $files[$i]
            $dst = [System.IO.Path]::ChangeExtension($src.FullName, ".mp4")
            $tmp = [System.IO.Path]::Combine(
                $src.DirectoryName,
                $src.BaseName + ".__pku_fix_tmp__.mp4"
            )

            $currentLabel.Text = "正在处理 ($($i + 1)/$($files.Count))：$($src.Name)"
            Set-ProgressSafe $currentProgress 0
            [System.Windows.Forms.Application]::DoEvents()

            if (Test-Path -LiteralPath $dst) {
                Add-Log "跳过：$($src.Name) —— 已存在同名 MP4，为避免覆盖，原 TS 保留。"
                $skipped++
                $overallPct = (($i + 1) / $files.Count) * 100
                Set-ProgressSafe $overallProgress $overallPct
                $overallLabel.Text = "总体进度：$([int]$overallPct)%"
                continue
            }

            if (Test-Path -LiteralPath $tmp) {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }

            $duration = Get-MediaDuration -Path $src.FullName
            $codecs = Get-CodecSummary -Path $src.FullName

            if ($duration -gt 0) {
                if ($codecs) {
                    Add-Log ("开始：{0}（约 {1:N1} 分钟；{2}）" -f $src.Name, ($duration / 60), $codecs)
                } else {
                    Add-Log ("开始：{0}（约 {1:N1} 分钟）" -f $src.Name, ($duration / 60))
                }
            } else {
                Add-Log "开始：$($src.Name)"
            }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $script:FfmpegPath
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true

            $srcQ = '"' + $src.FullName + '"'
            $tmpQ = '"' + $tmp + '"'
            $psi.Arguments = "-hide_banner -nostdin -loglevel error -y -i $srcQ -map 0:v? -map 0:a? -map_metadata 0 -c copy -movflags +faststart -progress pipe:1 -nostats $tmpQ"

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            $script:CurrentProcess = $proc
            [void]$proc.Start()

            $stderrTask = $proc.StandardError.ReadToEndAsync()

            while (-not $proc.StandardOutput.EndOfStream) {
                if ($script:CancelRequested) {
                    try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
                    break
                }

                $line = $proc.StandardOutput.ReadLine()

                if ($line -match '^out_time_us=(\d+)$' -and $duration -gt 0) {
                    $seconds = [double]$matches[1] / 1000000.0
                    $pct = [Math]::Min(99.0, ($seconds / $duration) * 100.0)
                    Set-ProgressSafe $currentProgress $pct
                    $overallPct = (($i + ($pct / 100.0)) / $files.Count) * 100.0
                    Set-ProgressSafe $overallProgress $overallPct
                    $overallLabel.Text = "总体进度：$([int]$overallPct)%"
                }
                elseif ($line -match '^out_time=(.+)$' -and $duration -gt 0) {
                    $ts = [TimeSpan]::Zero
                    if ([TimeSpan]::TryParse($matches[1], [ref]$ts)) {
                        $pct = [Math]::Min(99.0, ($ts.TotalSeconds / $duration) * 100.0)
                        Set-ProgressSafe $currentProgress $pct
                        $overallPct = (($i + ($pct / 100.0)) / $files.Count) * 100.0
                        Set-ProgressSafe $overallProgress $overallPct
                        $overallLabel.Text = "总体进度：$([int]$overallPct)%"
                    }
                }

                [System.Windows.Forms.Application]::DoEvents()
            }

            try { $proc.WaitForExit() } catch {}
            $stderr = ""
            try { $stderr = $stderrTask.Result } catch {}

            $exitCode = -1
            try { $exitCode = $proc.ExitCode } catch {}

            $script:CurrentProcess = $null

            if ($script:CancelRequested) {
                if (Test-Path -LiteralPath $tmp) {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
                Add-Log "已取消。$($src.Name) 的原 TS 已保留。"
                break
            }

            if ($exitCode -ne 0) {
                if (Test-Path -LiteralPath $tmp) {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
                $failed++
                Add-Log "失败：$($src.Name) —— 无法直接无损封装为 MP4，原 TS 已保留。"
                if ($stderr) {
                    $firstError = ($stderr -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join " | "
                    if ($firstError) { Add-Log "FFmpeg：$firstError" }
                }
                continue
            }

            if (-not (Test-Mp4 -Path $tmp)) {
                if (Test-Path -LiteralPath $tmp) {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                }
                $failed++
                Add-Log "失败：$($src.Name) —— 生成的 MP4 未通过 ffprobe 验证，原 TS 已保留。"
                continue
            }

            try {
                Move-Item -LiteralPath $tmp -Destination $dst -Force
                Remove-Item -LiteralPath $src.FullName -Force
                $success++
                Set-ProgressSafe $currentProgress 100
                Add-Log "成功：$($src.Name) → $([System.IO.Path]::GetFileName($dst))；原 TS 已删除。"
            } catch {
                $failed++
                Add-Log "警告：MP4 已生成，但删除/重命名时出错。错误：$($_.Exception.Message)"
            }

            $overallPct = (($i + 1) / $files.Count) * 100
            Set-ProgressSafe $overallProgress $overallPct
            $overallLabel.Text = "总体进度：$([int]$overallPct)%"
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($script:CancelRequested) {
            $currentLabel.Text = "已取消。"
            Add-Log "任务已取消。"
        } else {
            Set-ProgressSafe $overallProgress 100
            $overallLabel.Text = "总体进度：100%"
            $currentLabel.Text = "处理完成。"
            Add-Log ("完成：成功 {0}，失败 {1}，跳过 {2}。" -f $success, $failed, $skipped)

            [System.Windows.Forms.MessageBox]::Show(
                "处理完成。`r`n`r`n成功：$success`r`n失败：$failed`r`n跳过：$skipped`r`n`r`n只有成功并通过验证的文件才会删除原 TS。",
                "PKU-Art TS → MP4",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    }
    catch {
        Add-Log "程序异常：$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "程序发生异常：`r`n$($_.Exception.Message)`r`n`r`n原 TS 不会因为这个异常被主动删除。",
            "程序异常",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
    finally {
        $script:IsRunning = $false
        $script:CurrentProcess = $null
        $cancelButton.Enabled = $false
        $closeButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
