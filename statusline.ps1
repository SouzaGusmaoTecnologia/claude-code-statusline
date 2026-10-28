# Claude Code custom status line (2 lines)
# Reads session JSON from stdin and prints status info to stdout.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Get-Percent {
    param($Value)

    if ($null -eq $Value) { return $null }

    $num = $null
    $isFraction = $false
    if ($Value -is [string]) {
        $raw = $Value.Trim().Replace('%', '').Replace(',', '.')
        try {
            $num = [double]::Parse($raw, [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            return $null
        }
        $isFraction = $raw.Contains('.')
    } else {
        try {
            $num = [double]$Value
        } catch {
            return $null
        }
        $isFraction = ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal])
    }

    if ($isFraction -and $num -gt 0 -and $num -lt 1) {
        $num = $num * 100
    }

    $n = [math]::Round($num)
    if ($n -lt 0) { return 0 }
    if ($n -gt 100) { return 100 }
    return [int]$n
}

function New-Bar {
    param(
        [int]$Percent,
        [int]$Width = 10,
        [string]$FilledChar,
        [string]$EmptyChar
    )

    $filled = [math]::Floor(($Percent / 100.0) * $Width)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $Width) { $filled = $Width }
    $empty = $Width - $filled

    return ('[' + ($FilledChar * $filled) + ($EmptyChar * $empty) + ']')
}

function New-PrettyUsageDisplay {
    param([int]$Percent)

    $reset = "`e[0m"
    $filledBlock = [string][char]0x2588
    $emptyBlock = [string][char]0x2591
    $bar = New-Bar -Percent $Percent -Width 10 -FilledChar $filledBlock -EmptyChar $emptyBlock

    if ($Percent -lt 50) {
        return "`e[32m$bar $Percent%$reset"
    }
    if ($Percent -lt 65) {
        return "`e[33m$bar $Percent%$reset"
    }
    if ($Percent -lt 80) {
        return "`e[38;5;208m$bar $Percent%$reset"
    }
    return "`e[31m$bar $Percent%$reset"
}

function New-UnavailableDisplay {
    $reset = "`e[0m"
    return "`e[2m[░░░░░░░░░░] --$reset"
}

function Format-TimeRemaining {
    param([timespan]$Span)

    $totalMinutes = [int][math]::Floor($Span.TotalMinutes)
    if ($totalMinutes -lt 1) { return '<1m' }

    $days = [int][math]::Floor($totalMinutes / 1440)
    $hours = [int][math]::Floor(($totalMinutes % 1440) / 60)
    $minutes = $totalMinutes % 60

    if ($days -gt 0) { return "${days}d${hours}h" }
    if ($hours -gt 0) { return "${hours}h${minutes}m" }
    return "${minutes}m"
}

function New-ResetDisplay {
    param(
        $ResetsAt,
        [switch]$WithDate
    )

    if ($null -eq $ResetsAt -or "$ResetsAt" -eq '') { return '' }

    try {
        $epoch = [long]$ResetsAt
    } catch {
        return ''
    }

    try {
        $resetLocal = [DateTimeOffset]::FromUnixTimeSeconds($epoch).ToLocalTime()
    } catch {
        return ''
    }

    # Janela ja expirou: o dado em cache esta obsoleto, nao vale exibir.
    $span = $resetLocal - [DateTimeOffset]::Now
    if ($span.TotalSeconds -le 0) { return '' }

    # Mes abreviado em vez de numerico: "19/ago" nao se confunde com a hora "19:00" do 5h.
    $mesesPtBr = @('jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez')
    $stamp = if ($WithDate) {
        '{0:00}/{1} {2}' -f $resetLocal.Day, $mesesPtBr[$resetLocal.Month - 1], $resetLocal.ToString('HH:mm')
    } else {
        $resetLocal.ToString('HH:mm')
    }
    $remaining = Format-TimeRemaining -Span $span

    # Espaco apos o U+21BB: sem ele a fonte do terminal cola o glifo no digito seguinte.
    return "`e[2m ↻ $stamp ($remaining)`e[0m"
}

function Get-FirstNonNull {
    param([object[]]$Values)
    foreach ($v in $Values) {
        if ($null -ne $v -and "$v" -ne '') {
            return $v
        }
    }
    return $null
}

function Format-TokenCount {
    param([double]$Tokens)

    if ($Tokens -ge 1000000) {
        $v = $Tokens / 1000000.0
        if ($v -ge 10) { return ('{0:0}M' -f $v) }
        return ('{0:0.#}M' -f $v)
    }
    if ($Tokens -ge 1000) {
        $v = $Tokens / 1000.0
        if ($v -ge 10) { return ('{0:0}k' -f $v) }
        return ('{0:0.#}k' -f $v)
    }
    return ('{0:0}' -f $Tokens)
}

function New-ContextDisplay {
    param($ContextWindow)

    if ($null -eq $ContextWindow) {
        return New-UnavailableDisplay
    }

    $AUTO_COMPACT_BUFFER_PCT = 16.5
    $remainingRaw = $ContextWindow.remaining_percentage

    $used = $null
    if ($null -ne $remainingRaw) {
        try {
            $remaining = [double]$remainingRaw
            $usableRemaining = [math]::Max(0.0, (($remaining - $AUTO_COMPACT_BUFFER_PCT) / (100.0 - $AUTO_COMPACT_BUFFER_PCT)) * 100.0)
            $used = [int][math]::Round([math]::Max(0.0, [math]::Min(100.0, 100.0 - $usableRemaining)))
        } catch {
            $used = Get-Percent -Value $ContextWindow.used_percentage
        }
    } else {
        $used = Get-Percent -Value $ContextWindow.used_percentage
    }

    if ($null -eq $used) {
        return New-UnavailableDisplay
    }

    $tokenInfo = ''
    $usedTokens = $null
    $totalTokens = $ContextWindow.context_window_size
    $inTok = $ContextWindow.total_input_tokens
    $outTok = $ContextWindow.total_output_tokens
    if ($null -ne $inTok) {
        try { $usedTokens = [double]$inTok } catch {}
        if ($null -ne $outTok) {
            try { $usedTokens += [double]$outTok } catch {}
        }
    }
    if ($null -ne $usedTokens -and $null -ne $totalTokens) {
        try {
            $tokenInfo = ' ' + (Format-TokenCount -Tokens $usedTokens) + ' / ' + (Format-TokenCount -Tokens ([double]$totalTokens))
        } catch {}
    }

    return (New-PrettyUsageDisplay -Percent $used) + $tokenInfo
}

function Get-RateLimitRawValues {
    param($Data)

    $rl5Raw = Get-FirstNonNull @(
        $Data.rate_limits.five_hour.used_percentage,
        $Data.rate_limits.fiveHour.used_percentage,
        $Data.rate_limits.short_term.used_percentage,
        $Data.rate_limits.shortTerm.used_percentage,
        $Data.rate_limits.'5h'.used_percentage,
        $Data.rate_limit.five_hour.used_percentage
    )

    $rl7Raw = Get-FirstNonNull @(
        $Data.rate_limits.seven_day.used_percentage,
        $Data.rate_limits.sevenDay.used_percentage,
        $Data.rate_limits.long_term.used_percentage,
        $Data.rate_limits.longTerm.used_percentage,
        $Data.rate_limits.'7d'.used_percentage,
        $Data.rate_limit.seven_day.used_percentage
    )

    $rl5Reset = Get-FirstNonNull @(
        $Data.rate_limits.five_hour.resets_at,
        $Data.rate_limits.fiveHour.resets_at,
        $Data.rate_limits.short_term.resets_at,
        $Data.rate_limits.shortTerm.resets_at,
        $Data.rate_limits.'5h'.resets_at,
        $Data.rate_limit.five_hour.resets_at
    )

    $rl7Reset = Get-FirstNonNull @(
        $Data.rate_limits.seven_day.resets_at,
        $Data.rate_limits.sevenDay.resets_at,
        $Data.rate_limits.long_term.resets_at,
        $Data.rate_limits.longTerm.resets_at,
        $Data.rate_limits.'7d'.resets_at,
        $Data.rate_limit.seven_day.resets_at
    )

    return [pscustomobject]@{
        rl5 = $rl5Raw
        rl7 = $rl7Raw
        rl5Reset = $rl5Reset
        rl7Reset = $rl7Reset
    }
}

function Get-CacheCandidates {
    $userHome = [Environment]::GetFolderPath('UserProfile')
    $primary = Join-Path $userHome '.claude\cache\statusline-rate-limits.json'
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) 'claude-statusline-rate-limits.json'
    return @($primary, $temp)
}

function Read-RateLimitCache {
    $paths = Get-CacheCandidates
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) {
            try {
                return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json -Depth 5)
            } catch {
                # try next
            }
        }
    }
    return $null
}

function Write-RateLimitCache {
    param(
        [int]$Rl5Pct,
        [int]$Rl7Pct,
        $Rl5Reset,
        $Rl7Reset
    )

    $payload = [pscustomobject]@{
        rl5_pct = $Rl5Pct
        rl7_pct = $Rl7Pct
        rl5_reset = $Rl5Reset
        rl7_reset = $Rl7Reset
        updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }

    $paths = Get-CacheCandidates
    foreach ($p in $paths) {
        try {
            $cacheDir = Split-Path -Parent $p
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
            }
            $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $p -Encoding UTF8
            return
        } catch {
            # try next path
        }
    }
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-Output '[model?]  unknown | git: n/a'
    Write-Output 'CONTEXTO [░░░░░░░░░░] -- | TK5h [░░░░░░░░░░] -- | TK7D [░░░░░░░░░░] --'
    exit 0
}

try {
    $data = $raw | ConvertFrom-Json -Depth 20
} catch {
    Write-Output '[model?]  unknown | git: n/a'
    Write-Output 'CONTEXTO [░░░░░░░░░░] -- | TK5h [░░░░░░░░░░] -- | TK7D [░░░░░░░░░░] --'
    exit 0
}

$model = $data.model.display_name
if ([string]::IsNullOrWhiteSpace($model)) { $model = 'model?' }

# Versao do CLI: so aparece no banner de abertura, que rola para fora da tela
$cliVersion = $data.version
if ([string]::IsNullOrWhiteSpace($cliVersion)) {
    $modelPart = $model
} else {
    $modelPart = "$model v$cliVersion"
}

$dir = $data.workspace.current_dir
if ([string]::IsNullOrWhiteSpace($dir)) { $dir = $data.cwd }
if ([string]::IsNullOrWhiteSpace($dir)) { $dir = 'unknown' }
$folder = Split-Path -Leaf $dir
if ([string]::IsNullOrWhiteSpace($folder)) { $folder = $dir }

$rateRaw = Get-RateLimitRawValues -Data $data
$rl5Pct = Get-Percent -Value $rateRaw.rl5
$rl7Pct = Get-Percent -Value $rateRaw.rl7
$rl5Reset = $rateRaw.rl5Reset
$rl7Reset = $rateRaw.rl7Reset

if (($null -ne $rl5Pct) -or ($null -ne $rl7Pct)) {
    if ($null -eq $rl5Pct) { $rl5Pct = 0 }
    if ($null -eq $rl7Pct) { $rl7Pct = 0 }
    Write-RateLimitCache -Rl5Pct $rl5Pct -Rl7Pct $rl7Pct -Rl5Reset $rl5Reset -Rl7Reset $rl7Reset
} else {
    $cached = Read-RateLimitCache
    if ($null -ne $cached) {
        $cached5 = Get-Percent -Value $cached.rl5_pct
        $cached7 = Get-Percent -Value $cached.rl7_pct
        if ($null -ne $cached5) { $rl5Pct = $cached5 }
        if ($null -ne $cached7) { $rl7Pct = $cached7 }
        if ($null -eq $rl5Reset) { $rl5Reset = $cached.rl5_reset }
        if ($null -eq $rl7Reset) { $rl7Reset = $cached.rl7_reset }
    }
}

$gitText = 'git: n/a'
try {
    $inside = git -C $dir rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and ($inside -join '').Trim() -eq 'true') {
        $branch = (git -C $dir rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1).Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) { $branch = '(detached)' }

        $changes = git -C $dir status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and $changes -and $changes.Count -gt 0) {
            $gitText = "git: $branch *"
        } else {
            $gitText = "git: $branch ok"
        }
    }
} catch {
    $gitText = 'git: n/a'
}

$line1 = "$modelPart | $folder | $gitText"

$ctxPart = New-ContextDisplay -ContextWindow $data.context_window
$rl5Part = if ($null -eq $rl5Pct) { New-UnavailableDisplay } else { (New-PrettyUsageDisplay -Percent $rl5Pct) + (New-ResetDisplay -ResetsAt $rl5Reset) }
$rl7Part = if ($null -eq $rl7Pct) { New-UnavailableDisplay } else { (New-PrettyUsageDisplay -Percent $rl7Pct) + (New-ResetDisplay -ResetsAt $rl7Reset -WithDate) }

$line2 = "Contexto $ctxPart | Token 5h $rl5Part | Token 7D $rl7Part"

Write-Output $line1
Write-Output $line2

