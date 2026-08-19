# cp932_pipe_test.ps1
#
# Author:  Yoggy (@yoggydev)  https://github.com/yoggydev
# License: MIT
#
# Measured on a Japanese-locale Windows machine (ACP=932) by @yoggydev.
# Drafted with Claude; the measurements are @yoggydev's.
#
# Measures the ja-JP / CP932 side of NousResearch/hermes-agent#89442.
# No Python required. Windows PowerShell 5.1 or PowerShell 7, either is fine.
#
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\cp932_pipe_test.ps1
#
# The source of this file is ASCII-only on purpose, so it cannot be broken by
# the very bug it measures. Saved as UTF-8 with BOM + CRLF anyway, to match the
# .editorconfig rule in stickman-video-director.
#
# Console output is ASCII-only. The full result, including Japanese text, is
# written to cp932_pipe_test_result.txt as UTF-8 with BOM.

$ErrorActionPreference = 'Continue'
$script:OUT = New-Object System.Collections.Generic.List[string]

function Log {
    param(
        [Parameter(Position = 0)][string]$Console = '',
        [Parameter(Position = 1)][string]$File = ''
    )
    Write-Host $Console
    if ([string]::IsNullOrEmpty($File)) { $script:OUT.Add($Console) }
    else { $script:OUT.Add($File) }
}

function Count-Char {
    param([string]$Text, [char]$Needle)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $n = 0
    foreach ($c in $Text.ToCharArray()) { if ($c -eq $Needle) { $n++ } }
    return $n
}

function Show-Bytes {
    param([byte[]]$Bytes, [int]$Max = 64)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '(none)' }
    $n = [Math]::Min($Bytes.Length, $Max)
    $parts = @()
    for ($i = 0; $i -lt $n; $i++) { $parts += ('{0:X2}' -f $Bytes[$i]) }
    return ($parts -join ' ')
}

$enc932  = [System.Text.Encoding]::GetEncoding(932)
$encUtf8 = [System.Text.Encoding]::UTF8    # replacement fallback by default
$FFFD    = [char]0xFFFD

# Strict variant: throws on an unassigned byte pair instead of quietly
# substituting something. Needed for the sweep, otherwise every pair looks
# valid and the count is wrong.
$enc932Strict = [System.Text.Encoding]::GetEncoding(
    932,
    [System.Text.EncoderFallback]::ExceptionFallback,
    [System.Text.DecoderFallback]::ExceptionFallback)

# --------------------------------------------------------------- environment
Log "== environment =="
Log ("PSVersion               = " + $PSVersionTable.PSVersion.ToString())
Log ("PSEdition               = " + $PSVersionTable.PSEdition)

$acp = 'unreadable'
try {
    $acp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction Stop).ACP
} catch { }
Log ("ANSI code page (ACP)    = " + $acp)
Log ("Console::OutputEncoding = " + [Console]::OutputEncoding.CodePage + " (" + [Console]::OutputEncoding.WebName + ")")
Log ("Encoding::Default       = " + [System.Text.Encoding]::Default.CodePage)

try { Log ("system locale           = " + (Get-WinSystemLocale).Name) }
catch { Log "system locale           = (unavailable)" }

foreach ($n in @('python', 'python3', 'py')) {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($c) { Log ("interpreter found       = " + $n + " -> " + $c.Source) }
}
Log ""

if ("$acp" -ne '932') {
    Log "!! ACP is not 932 -- this is not a Japanese-locale Windows."
    Log "!! T1 still produces valid CP932 numbers, but say so plainly when reporting."
    Log ""
}

# --------------------------------------------- helper: run and capture raw bytes
function Invoke-CaptureRaw {
    param([string]$FileName, [string]$Arguments)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $FileName
    $psi.Arguments              = $Arguments
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow         = $true

    try {
        $p = [System.Diagnostics.Process]::Start($psi)
    } catch {
        return @{ Err = [byte[]]@(); Out = [byte[]]@(); Code = -1; Failed = $_.Exception.Message }
    }

    $errMs = New-Object System.IO.MemoryStream
    $p.StandardError.BaseStream.CopyTo($errMs)
    $outMs = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($outMs)
    $p.WaitForExit()

    return @{ Err = $errMs.ToArray(); Out = $outMs.ToArray(); Code = $p.ExitCode; Failed = '' }
}

# --------------------------------------------------------------- T1 deterministic
# A child process writes a known CP932 byte sequence to stderr. No Japanese
# language pack is needed, so this produces the same bytes on any Windows.
#
# The sequence decodes to an ordinary Japanese sentence. It was chosen because
# it contains FOUR characters whose SECOND byte is 0x5C:
#     8F5C   975C   8D5C   835C
# Those do not vanish -- they turn into a stray backslash, which is why the
# damage is easy to misread as a path bug instead of an encoding bug.
# The decoded text is written to the result file, so you can read it there.

$msgBytes = @(
    0x8F,0x5C,0x95,0xAA,0x82,0xC8,0x97,0x5C,0x92,0xE8,0x82,0xF0,0x8D,0x5C,
    0x90,0xAC,0x82,0xC5,0x82,0xAB,0x82,0xDC,0x82,0xB9,0x82,0xF1,0x3A,0x20,
    0x83,0x5C,0x81,0x5B,0x83,0x58,0x82,0xAA,0x8C,0xA9,0x82,0xC2,0x82,0xA9,
    0x82,0xE8,0x82,0xDC,0x82,0xB9,0x82,0xF1
)

Log "== T1) deterministic CP932 bytes through a pipe =="
Log ("bytes written by child   : " + $msgBytes.Count)

$list  = (($msgBytes | ForEach-Object { '0x{0:X2}' -f $_ }) -join ',')
$inner = "`$b=[byte[]]@($list);`$s=[Console]::OpenStandardError();`$s.Write(`$b,0,`$b.Length);`$s.Flush()"
$b64   = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($inner))

$hostExe = ''
try { $hostExe = (Get-Process -Id $PID).Path } catch { }
if ([string]::IsNullOrEmpty($hostExe)) { $hostExe = 'powershell.exe' }
Log ("child host               : " + $hostExe)

$r1   = Invoke-CaptureRaw -FileName $hostExe -Arguments "-NoProfile -EncodedCommand $b64"
$raw1 = $r1.Err

Log ("bytes received by parent : " + $raw1.Length)
Log ("first bytes              : " + (Show-Bytes $raw1))

$identical = ($raw1.Length -eq $msgBytes.Count)
if ($identical) {
    for ($i = 0; $i -lt $raw1.Length; $i++) {
        if ($raw1[$i] -ne $msgBytes[$i]) { $identical = $false; break }
    }
}
Log ("pipe delivered unchanged : " + $identical)
Log ""

if ($raw1.Length -gt 0) {
    $asUtf8     = $encUtf8.GetString($raw1)
    $nFffd      = Count-Char $asUtf8 $FFFD
    $nBackslash = Count-Char $asUtf8 ([char]'\')

    Log "-- decoded as UTF-8 with replacement (what the current code does) --"
    Log ("  chars     = " + $asUtf8.Length)
    Log ("  U+FFFD    = " + $nFffd)
    Log ("  stray '\' = " + $nBackslash + "   <- these were 0x5C trail bytes of kanji")
    Log "  text      = (written to result file)" ("  text      = " + $asUtf8)
    Log ""

    $as932    = $enc932.GetString($raw1)
    $n932Fffd = Count-Char $as932 $FFFD

    Log "-- decoded as CP932 from the raw bytes (what the fix should do) --"
    Log ("  chars     = " + $as932.Length)
    Log ("  U+FFFD    = " + $n932Fffd)
    Log "  text      = (written to result file)" ("  text      = " + $as932)
    Log ""
} else {
    Log "!! child wrote nothing to stderr -- report this as-is, do not guess"
    Log ""
}

# ---------------------------------------------------------------- T2 real error
Log "== T2) a real native Windows program's localized error =="
$r2 = Invoke-CaptureRaw -FileName 'cmd.exe' -Arguments '/c dir Z:\__no_such_dir__'
if (-not [string]::IsNullOrEmpty($r2.Failed)) {
    Log ("could not start cmd.exe : " + $r2.Failed)
}

$raw2 = $r2.Err
$from = 'stderr'
if ($raw2.Length -eq 0) { $raw2 = $r2.Out; $from = 'stdout' }

Log ("captured from            : " + $from)
Log ("bytes                    : " + $raw2.Length)
Log ("first bytes              : " + (Show-Bytes $raw2))

$hasHigh = $false
foreach ($b in $raw2) { if ($b -ge 0x80) { $hasHigh = $true; break } }
Log ("contains non-ASCII bytes : " + $hasHigh)

if ($hasHigh) {
    $u = $encUtf8.GetString($raw2)
    $f = Count-Char $u $FFFD
    $j = $enc932.GetString($raw2)
    Log ("  utf-8+replace U+FFFD   = " + $f + " / " + $u.Length + " chars")
    Log "  cp932 decode           = (written to result file)" ("  cp932 decode           = " + $j)
} else {
    Log "  message is pure ASCII -- this Windows UI language is not Japanese."
    Log "  T1 remains the valid data point. State that plainly when reporting."
}
Log ""

# ------------------------------------------------------------------ C / D sweep
# Uses Windows' own code page 932 tables, so this is an independent check
# against the same sweep done with Python's cp932 codec.
Log "== D) CP932 double-byte sweep, using Windows' own 932 tables =="

$leads  = @(0x81..0x9F) + @(0xE0..0xFC)
$trails = @(0x40..0x7E) + @(0x80..0xFC)

$total    = 0
$survUtf8 = 0
$surv932  = 0
$t5cChars = New-Object System.Collections.Generic.List[string]
$t5cCodes = New-Object System.Collections.Generic.List[string]

foreach ($l in $leads) {
    foreach ($t in $trails) {
        $pair = [byte[]]@($l, $t)
        $s = $null
        try { $s = $enc932Strict.GetString($pair) } catch { continue }
        if ($null -eq $s -or $s.Length -ne 1) { continue }
        if ($s[0] -eq $FFFD) { continue }
        $total++
        if ($encUtf8.GetString($pair) -eq $s) { $survUtf8++ }
        if ($enc932.GetString($pair) -eq $s) { $surv932++ }
        if ($t -eq 0x5C) {
            $t5cChars.Add($s)
            $t5cCodes.Add(('{0:X2}5C' -f $l))
        }
    }
}

Log ("double-byte chars enumerated : " + $total)
Log ("  survive utf-8 + replace    : " + $survUtf8)
Log ("  survive raw bytes + cp932  : " + $surv932)
Log ""
Log "NOTE: measured per character in isolation. In a real byte stream a CP932"
Log "      character followed by other bytes can occasionally form valid UTF-8."
Log "      Do not state this as 'every byte in every stream'."
Log ""

Log "== C) CP932 characters whose SECOND byte is 0x5C =="
Log ("count = " + $t5cChars.Count)
Log "  characters = (written to result file)" ("  characters = " + ($t5cChars -join ''))
Log ("  codes      = " + ($t5cCodes -join ' '))
Log ""

# ------------------------------------------------------------------- write out
$path = Join-Path (Get-Location).Path 'cp932_pipe_test_result.txt'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($path, (($script:OUT -join "`r`n") + "`r`n"), $utf8Bom)
Write-Host ""
Write-Host ("full result (UTF-8 BOM, CRLF) written to: " + $path)
