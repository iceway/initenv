<#
Windows powershell 中管理员权限执行以下命令可以修复 winget 无法找到的错误：
    Install-Module -Name Microsoft.WinGet.Client -Force
    Repair-WinGetPackageManager
通过以下命令查看已经安装的 powershell 模块
    Get-InstalledModule
#>

<#=============================================================================
  名称: winget-install.ps1
  用途: 通过 winget 批量安装应用程序，自动检测并代理加速 GitHub 下载
  作者: initenv

  用法:
    .\winget-install.ps1 [-u] <winget-export.json>
    .\winget-install.ps1 [-u] <PackageId1> [PackageId2 ...]
    .\winget-install.ps1 [-u] export.json PackageId1 PackageId2

  示例:
    .\winget-install.ps1 Microsoft.VisualStudioCode
    .\winget-install.ps1 -u Microsoft.VisualStudioCode
    .\winget-install.ps1 .\packages.json
    winget export -o .\packages.json

  注意事项:
    1. 需要 Windows 10 1809+ 或 Windows 11，且已安装 winget（应用安装程序）。
    2. 需要网络连接，且能访问 gh-proxy.org 代理服务。
    3. 如果 gh-proxy.org 不可用，可修改 $PROXY_PREFIX 变量替换为其他代理地址。
    4. winget export 导出的 JSON 文件格式固定，参照 winget 官方格式。
    5. 本脚本会自动接受包许可协议（--accept-package-agreements），请注意合规性。
#============================================================================#>

param(
    [Alias('u')]
    [switch]$UpgradeMode,
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arguments
)

# 错误处理策略：Continue 表示遇到非终止错误时继续执行，不中断脚本
$ErrorActionPreference = 'Continue'

#=============================================================================
# 配置项
#=============================================================================
# 代理重试次数上限（每次检测到 GitHub URL 算一次重试，最大尝试次数 = 该值 + 1）
$MAX_RETRIES = 3
# 连接超时时间（秒），在此期间子进程无任何输出则判定超时
$TIMEOUT_SECONDS = 120
# GitHub URL 匹配正则
$GITHUB_URL_PATTERN = 'https://github\.com/\S+'
# GitHub 代理前缀（可替换为其他代理服务地址）
$PROXY_PREFIX = 'https://gh-proxy.org'

#=============================================================================
# Ctrl+C 处理
#=============================================================================
$script:aborted = $false
$script:currentProc = $null
$script:ctrlCHandler = [System.EventHandler[System.ConsoleCancelEventArgs]]{
    param($sender, $e)
    $e.Cancel = $true
    $script:aborted = $true
    if ($script:currentProc -and -not $script:currentProc.HasExited) {
        $script:currentProc.Kill()
    }
}
if ($null -ne [Console]::CancelKeyPress) {
    [Console]::CancelKeyPress.Add($script:ctrlCHandler)
}

#=============================================================================
# 颜色输出辅助
# 使用 Write-Host 的 -ForegroundColor 参数区分不同级别的输出信息
#   Cyan  : 步骤/进度提示
#   Green : 成功信息
#   Red   : 失败/错误信息
#   Yellow: 跳过/警告信息
#   Gray  : winget 原始输出（与脚本自身信息区分）
#=============================================================================
$C = @{
    Step    = 'Cyan'
    Success = 'Green'
    Fail    = 'Red'
    Skip    = 'Yellow'
    Trace   = 'DarkGray'
}

function Write-Step    { param([string]$m) Write-Host $m -ForegroundColor $C.Step }
function Write-Success { param([string]$m) Write-Host $m -ForegroundColor $C.Success }
function Write-Fail    { param([string]$m) Write-Host $m -ForegroundColor $C.Fail }
function Write-Skip    { param([string]$m) Write-Host $m -ForegroundColor $C.Skip }
function Write-Trace   { param([string]$m) Write-Host $m -ForegroundColor $C.Trace }

#=============================================================================
# 函数: Get-PackagesFromJson
# 用途: 从 winget export 导出的 JSON 文件中提取所有包标识符列表
# 输入: JSON 文件路径
# 输出: 字符串列表
# JSON 格式参考:
#   { "Sources": [ { "Packages": [ { "PackageIdentifier": "..." }, ... ] } ] }
#=============================================================================
function Get-PackagesFromJson {
    param([string]$Path)
    $json = Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($source in $json.Sources) {
        foreach ($pkg in $source.Packages) {
            $result.Add($pkg.PackageIdentifier)
        }
    }
    return $result
}

#=============================================================================
# 函数: Test-PackageInstalled
# 用途: 检查指定包 ID 是否已在当前系统中安装
# 原理: 调用 winget list --id <包ID>，退出码为 0 表示已安装
# 注意: 基于 winget 的包管理器数据库，无法检测手动安装的同款软件
#=============================================================================
function Test-PackageInstalled {
    param([string]$PackageId)
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = @{
        FileName                = 'winget'
        Arguments               = "list --id `"$PackageId`""
        UseShellExecute         = $false
        RedirectStandardOutput  = $true
        RedirectStandardError   = $true
        CreateNoWindow          = $true
    }
    $proc.Start() | Out-Null
    $proc.WaitForExit()
    return ($proc.ExitCode -eq 0)
}

#=============================================================================
# 函数: Find-WinGetCacheDir
# 用途: 在 %TEMP%\WinGet\ 下查找 winget 自动生成的、与包 ID 最匹配的缓存目录
# 匹配策略:
#   1. 优先匹配名称以包 ID 开头的目录（通配符匹配）
#   2. 若有多个匹配，取最后修改时间最新的
#   3. 若没有名称匹配，回退取最新修改的目录
#=============================================================================
function Find-WinGetCacheDir {
    param([string]$PackageId)

    $wingetCache = Join-Path $env:TEMP 'WinGet'
    if (-not (Test-Path $wingetCache)) { return $null }

    $matched = Get-ChildItem -Path $wingetCache -Directory |
        Where-Object { $_.Name -like "$PackageId*" } |
        Sort-Object LastWriteTime -Descending

    if ($matched.Count -gt 0) {
        return $matched[0].FullName
    }

    $newest = Get-ChildItem -Path $wingetCache -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $newest) { return $null }
    return $newest.FullName
}

#=============================================================================
# 函数: Invoke-WingetInstallWithProxy
# 用途: 核心安装函数 - 执行 winget install，实时监控输出中的 GitHub 下载链接，
#       发现后中断 winget，通过代理下载安装包，然后重试 winget 安装。
# 参数: $PackageId - winget 包标识符
# 流程:
#   1. 循环尝试（最多 $MAX_RETRIES + 1 次）
#   2. 启动 winget install 进程，实时读取输出
#   3. 如果发现 GitHub URL，Kill 进程
#   4. 查找缓存目录，通过代理下载安装包
#   5. 重试 winget install
#=============================================================================
function Invoke-WingetInstallWithProxy {
    param(
        [string]$PackageId,
        [switch]$UpgradeMode
    )

    $command = if ($UpgradeMode) { 'upgrade' } else { 'install' }
    $pkgDir = $null

    for ($attempt = 1; $attempt -le ($MAX_RETRIES + 1); $attempt++) {
        $githubUrl = $null

        if ($attempt -eq 1) {
            Write-Step ">>> [${attempt}] 启动 winget ${command} --id ${PackageId} ..."
        } else {
            Write-Step ">>> [${attempt}] 重新 ${command} --id ${PackageId}（代理下载后重试）..."
        }

        $psi = [System.Diagnostics.ProcessStartInfo]@{
            FileName                = 'winget'
            Arguments               = "$command --accept-package-agreements --accept-source-agreements --id `"$PackageId`""
            UseShellExecute         = $false
            RedirectStandardOutput  = $true
            RedirectStandardError   = $true
            CreateNoWindow          = $true
            StandardOutputEncoding  = [System.Text.Encoding]::UTF8
            StandardErrorEncoding   = [System.Text.Encoding]::UTF8
        }
        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        $proc.Start() | Out-Null
        $script:currentProc = $proc

        # ---- 实时读取 stdout，检查 GitHub URL 和超时 ----
        # winget 使用 \r 实现实时动画（旋转符和进度条），
        # ReadLine 会把每个 \r 当作换行，导致动画每一帧变成独立行。
        # 以下正则匹配这些动画/进度行，过滤掉以保持输出整洁。
        $progressRe = '[▒█]'
        $spinnerRe  = '^\s+[-\\|/]\s*$'
        $lastActivity = [DateTime]::Now
        $timeoutDetected = $false

        $stdout = $proc.StandardOutput
        try {
            while ($true) {
                if ($script:aborted) { break }

                $readTask = $stdout.ReadLineAsync()
                try {
                    while (-not $readTask.Wait(500)) {
                        if ($script:aborted -or $timeoutDetected) { break }
                        if (([DateTime]::Now - $lastActivity).TotalSeconds -ge $TIMEOUT_SECONDS) {
                            $timeoutDetected = $true
                            break
                        }
                    }
                } catch {
                    break
                }

                if ($timeoutDetected -or $script:aborted) { break }

                try {
                    $line = $readTask.Result
                } catch {
                    break
                }
                if ($null -eq $line) { break }
                $lastActivity = [DateTime]::Now

                $isAnimation = ($line -match $spinnerRe) -or ($line -match $progressRe)
                if (-not $isAnimation) {
                    Write-Trace $line
                }
                if (-not $githubUrl) {
                    $m = [regex]::Match($line, $GITHUB_URL_PATTERN)
                    if ($m.Success) {
                        $githubUrl = $m.Value
                        Write-Skip "  [!] 检测到 GitHub 下载链接"
                        Write-Trace "    URL: $githubUrl"
                        break
                    }
                }
            }
        } catch {
            $script:aborted = $true
        }

        # 用户按下 Ctrl+C，跳过此包
        if ($script:aborted) {
            if (-not $proc.HasExited) { $proc.Kill() }
            Write-Skip "  [!] 跳过: $PackageId"
            $script:aborted = $false
            return
        }

        # 子进程可能还在运行（超时 / 检测到 GitHub URL），终止之
        if (-not $proc.HasExited) { $proc.Kill() }

        # ---- 读取 stderr ----
        $errorOutput = $proc.StandardError.ReadToEnd()
        if ($errorOutput) {
            Write-Trace $errorOutput
            if (-not $githubUrl) {
                $m = [regex]::Match($errorOutput, $GITHUB_URL_PATTERN)
                if ($m.Success) { $githubUrl = $m.Value; Write-Skip "  [!] 检测到 GitHub 下载链接 (stderr)" }
            }
        }

        $proc.WaitForExit()

        # ---- 超时重试 ----
        if ($timeoutDetected) {
            Write-Fail "  [x] 连接超时（${TIMEOUT_SECONDS}秒无响应）"
            if ($attempt -le $MAX_RETRIES) {
                Write-Skip "  [!] 第 ${attempt} 次重试..."
                Start-Sleep -Seconds 2
                continue
            }
            Write-Fail "  [x] 已达到最大重试次数，跳过: $PackageId"
            break
        }

        # ---- 需要代理下载 ----
        if ($githubUrl -and $attempt -le $MAX_RETRIES) {
            $githubUrl = $githubUrl.TrimEnd('.', ')', ']', '>', '"', "'", ',', ';')

            # 查找 winget 缓存目录
            Write-Step "  [v] 查找 winget 下载缓存目录 ..."
            Start-Sleep -Milliseconds 300
            $pkgDir = Find-WinGetCacheDir $PackageId

            if (-not $pkgDir) {
                $fallbackName = $PackageId -replace '[^\w\.-]', '_'
                $pkgDir = Join-Path $env:TEMP 'WinGet' $fallbackName
                $null = New-Item -ItemType Directory -Path $pkgDir -Force
                Write-Skip "  [!] 未找到 winget 缓存目录，创建回退目录: $pkgDir"
            } else {
                Write-Step "  [v] 找到 winget 缓存目录: $pkgDir"
            }

            # 通过代理下载
            $proxyUrl = "$PROXY_PREFIX/$githubUrl"
            $fileName = [System.IO.Path]::GetFileName($githubUrl.TrimEnd('/'))
            if ([string]::IsNullOrEmpty($fileName)) { $fileName = 'installer.exe' }
            $outFile = Join-Path $pkgDir $fileName

            Write-Step "  [v] 通过 gh-proxy 代理下载 GitHub 资源 ..."
            Write-Trace "      源 URL: $githubUrl"
            Write-Step "      代理 URL: $proxyUrl"
            Write-Step "      保存路径: $outFile"

            try {
                $wc = [System.Net.WebClient]::new()
                $wc.DownloadFile($proxyUrl, $outFile)
                Write-Success "  [v] 代理下载完成，准备重试 winget ${command}"
            } catch {
                Write-Fail "  [x] 代理下载失败: $_"
            }
            continue
        }

        # ---- 检查操作结果 ----
        $actionLabel = if ($UpgradeMode) { '升级' } else { '安装' }
        if ($proc.ExitCode -eq 0) {
            Write-Success "[OK] ${actionLabel}成功: $PackageId"
        } else {
            Write-Fail "[FAIL] ${actionLabel}失败: $PackageId，退出码: $($proc.ExitCode)"
        }
        break
    }
}

#=============================================================================
# 函数: Show-Help
# 用途: 输出详细的脚本用法说明
#=============================================================================
function Show-Help {
    Write-Step "+--------------------------------------------------------------------+"
    Write-Step "|   winget-install.ps1 - 批量安装 winget 包，代理加速 GitHub    |"
    Write-Step "+--------------------------------------------------------------------+"
    Write-Host ""
    Write-Step "【用法】"
    Write-Step "  .\winget-install.ps1 [-u] <winget-export.json>"
    Write-Step "  .\winget-install.ps1 [-u] <PackageId1> [PackageId2 ...]"
    Write-Step "  .\winget-install.ps1 [-u] export.json PackageId1 PackageId2"
    Write-Host ""
    Write-Step "【说明】"
    Write-Step "  读取 winget export 导出的 JSON 文件或直接指定包 ID，批量执行"
    Write-Step "  winget install/upgrade。安装过程中自动检测 GitHub 下载链接，中断后用"
    Write-Step "  gh-proxy 代理加速下载，然后重试安装，避免 GitHub 网络问题。"
    Write-Host ""
    Write-Step "【参数】"
    Write-Step "  -u                  升级模式，使用 winget upgrade 替代 install"
    Write-Step "  winget-export.json  winget export 导出的 JSON 文件路径"
    Write-Step "  PackageId           要安装的包标识符（如 Microsoft.VisualStudioCode）"
    Write-Step "                      支持同时指定多个包 ID"
    Write-Host ""
    Write-Step "【示例】"
    Write-Step "  # 指定一个包直接安装"
    Write-Step "  .\winget-install.ps1 Microsoft.VisualStudioCode"
    Write-Host ""
    Write-Step "  # 升级指定包"
    Write-Step "  .\winget-install.ps1 -u Microsoft.VisualStudioCode"
    Write-Host ""
    Write-Step "  # 指定多个包"
    Write-Step "  .\winget-install.ps1 7zip.7zip Google.Chrome Microsoft.VisualStudioCode"
    Write-Host ""
    Write-Step "  # 先导出已安装包列表，再批量安装"
    Write-Step "  winget export -o .\packages.json"
    Write-Step "  .\winget-install.ps1 .\packages.json"
    Write-Host ""
    Write-Step "  # JSON 文件 + 额外包 ID 混合"
    Write-Step "  .\winget-install.ps1 .\packages.json Microsoft.VisualStudioCode"
    Write-Host ""
    Write-Step "【行为说明】"
    Write-Step "  1. 安装模式（不带 -u）：安装前通过 winget list 检查包是否已存在，已安装则跳过"
    Write-Step "  2. 升级模式（带 -u）：跳过已安装检查，直接执行 winget upgrade"
    Write-Step "  3. 安装时实时监控 winget 输出，检测 GitHub 下载链接"
    Write-Step "  4. 发现 GitHub 链接立即中断 winget，通过 gh-proxy 代理下载"
    Write-Step "  5. 下载完成后重试 winget（最多重试 ${MAX_RETRIES} 次）"
    Write-Step "  6. 自动接受包许可协议和安全源协议（--accept-package-agreements）"
    Write-Step "  7. 子进程 ${TIMEOUT_SECONDS} 秒无输出则判定超时，自动终止并重试"
    Write-Step "  8. 按 Ctrl+C 可跳过当前正在处理的包，继续处理剩余包"
    Write-Host ""
    Write-Step "【配置】"
    Write-Step "  PROXY_PREFIX   GitHub 代理前缀（默认: https://gh-proxy.org）"
    Write-Step "  MAX_RETRIES      代理下载后重试次数（默认: ${MAX_RETRIES}）"
    Write-Step "  TIMEOUT_SECONDS  子进程超时时间（秒，默认: ${TIMEOUT_SECONDS}）"
    Write-Host ""
    Write-Step "【注意事项】"
    Write-Step "  1. 需要 Windows 10 1809+ / Windows 11，已安装 winget"
    Write-Step "  2. 请确保能访问 gh-proxy.org（或修改 PROXY_PREFIX）"
    Write-Step "  3. 自动接受协议的含义请自行了解并确保合规"
    Write-Host ""
}

#=============================================================================
# 主程序入口
#=============================================================================

# 未传参或传了帮助标志时显示帮助
$helpFlags = @('-?', '/?', '-help', '--help', '/help')
if ($Arguments.Count -eq 0 -or ($Arguments.Count -eq 1 -and $helpFlags -contains $Arguments[0])) {
    Show-Help
    exit 0
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail "未找到 winget。请确保已安装 '应用安装程序' (App Installer)。"
    exit 1
}

# 解析包标识符列表
$packages = [System.Collections.Generic.List[string]]::new()

if (Test-Path $Arguments[0] -PathType Leaf) {
    $ext = [System.IO.Path]::GetExtension($Arguments[0])
    if ($ext -eq '.json') {
        Write-Step "正在从 winget export 文件读取包列表: $($Arguments[0])"
        $jsonPkgs = Get-PackagesFromJson $Arguments[0]
        foreach ($pkg in $jsonPkgs) { $packages.Add($pkg) }
        for ($i = 1; $i -lt $Arguments.Count; $i++) {
            $packages.Add($Arguments[$i])
        }
    } else {
        foreach ($arg in $Arguments) { $packages.Add($arg) }
    }
} else {
    foreach ($arg in $Arguments) { $packages.Add($arg) }
}

if ($packages.Count -eq 0) {
    Write-Fail "没有需要安装的包。"
    exit 1
}

$total = $packages.Count
Write-Step "待安装的包（共 ${total} 个）: $($packages -join ', ')"
Write-Host ""

$actionLabel = if ($UpgradeMode) { '升级' } else { '安装' }
$index = 0
foreach ($pkg in $packages) {
    $script:aborted = $false
    $index++
    Write-Step "--- [${index}/${total}] 检查: ${pkg} ---"

    if (-not $UpgradeMode -and (Test-PackageInstalled $pkg)) {
        Write-Skip "[SKIP] 包 '$pkg' 已安装在当前系统中，跳过。"
        Write-Host ""
        continue
    }

    Write-Step "[>] 开始${actionLabel}: ${pkg}"
    Write-Host ""
    try {
        Invoke-WingetInstallWithProxy -PackageId $pkg -UpgradeMode:$UpgradeMode
    } catch {
        Write-Skip "  [!] 跳过: $PackageId（异常: $_）"
        $script:aborted = $false
    }
    Write-Host ""
}

Write-Success "全部完成。"

if ($null -ne [Console]::CancelKeyPress -and $null -ne $script:ctrlCHandler) {
    [Console]::CancelKeyPress.Remove($script:ctrlCHandler)
}
