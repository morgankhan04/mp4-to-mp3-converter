param([switch]$NoPause, [switch]$NoOpen, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Files)
$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'MP4 to MP3 Converter'
$ff = Join-Path $PSScriptRoot 'ffmpeg.exe'
function Finish { if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }; exit }
if (-not (Test-Path -LiteralPath $ff)) { Write-Host 'ffmpeg.exe is missing. Keep it in the same folder as this converter.' -ForegroundColor Red; Finish }

$exts = '.mp4','.m4v','.mov','.mkv'
if (-not $Files -or $Files.Count -eq 0) {
  Write-Host 'MP4 to MP3 Converter' -ForegroundColor Green
  Write-Host ''
  Write-Host 'Drag one or more videos into this window, then press Enter.' -ForegroundColor Cyan
  Write-Host '(Or just press Enter to convert every video in the app folder.)'
  $line = Read-Host '>'
  $Files = @([regex]::Matches($line, '"([^"]+)"|(\S+)') | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
  if ($Files.Count -eq 0) {
    Write-Host "Converting every video in: $PSScriptRoot"
    $Files = @(Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object { $exts -contains $_.Extension.ToLower() } | ForEach-Object { $_.FullName })
  }
}
$Files = @($Files | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($Files.Count -eq 0) { Write-Host 'No video files found to convert.' -ForegroundColor Yellow; Finish }

function Fmt([double]$s) { $t = [TimeSpan]::FromSeconds([math]::Max(0,$s)); '{0}:{1:00}:{2:00}' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds }
function Bar([double]$pct, [double]$done, [double]$total) {
  $w = 30; $n = [int][math]::Round($pct / 100 * $w)
  $bar = ('#' * $n) + ('-' * ($w - $n))
  Write-Host ("`r  [{0}] {1,3}%   {2} / {3}   " -f $bar, [int]$pct, (Fmt $done), (Fmt $total)) -NoNewline
}

$saved = @(); $failed = 0; $i = 0
foreach ($in in $Files) {
  $i++
  $item = Get-Item -LiteralPath $in
  $out = Join-Path $item.DirectoryName ($item.BaseName + '.mp3')
  Write-Host ''
  Write-Host ("File {0} of {1}: {2}" -f $i, $Files.Count, $item.Name) -ForegroundColor Cyan
  $n = 2
  while (Test-Path -LiteralPath $out) { $out = Join-Path $item.DirectoryName ("{0} ({1}).mp3" -f $item.BaseName, $n); $n++ }
  if ($n -gt 2) { Write-Host '  An MP3 with that name already exists, so this one gets a new name.' -ForegroundColor Yellow }
  Write-Host ("  Saving to: {0}" -f $out)

  $total = 0
  $info = & $ff -hide_banner -i $in 2>&1 | ForEach-Object { "$_" }
  $m = [regex]::Match(($info -join "`n"), 'Duration:\s*(\d+):(\d+):([\d\.]+)')
  if ($m.Success) { $total = [int]$m.Groups[1].Value*3600 + [int]$m.Groups[2].Value*60 + [double]::Parse($m.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture) }

  $prog = [IO.Path]::GetTempFileName(); $errf = [IO.Path]::GetTempFileName()
  $args = "-hide_banner -loglevel error -nostats -n -progress `"$prog`" -i `"$in`" -vn -c:a libmp3lame -q:a 0 -map_metadata 0 `"$out`""
  $p = Start-Process -FilePath $ff -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardError $errf
  $null = $p.Handle
  Bar 0 0 $total
  while (-not $p.HasExited) {
    Start-Sleep -Milliseconds 300
    try {
      $txt = [IO.File]::ReadAllText($prog)
      $ms = [regex]::Matches($txt, 'out_time_us=(\d+)')
      if ($ms.Count -gt 0 -and $total -gt 0) {
        $done = [double]$ms[$ms.Count-1].Groups[1].Value / 1000000
        Bar ([math]::Min(99, $done / $total * 100)) $done $total
      }
    } catch {}
  }
  $p.WaitForExit()
  $ok = (Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Length -gt 0) -and ($p.ExitCode -eq 0 -or $p.ExitCode -eq $null)
  if ($ok) {
    Bar 100 $total $total
    Write-Host ''
    Write-Host '  Done.' -ForegroundColor Green
    $saved += $out
  } else {
    Write-Host ''
    Write-Host '  FAILED to convert this file.' -ForegroundColor Red
    Get-Content -LiteralPath $errf -ErrorAction SilentlyContinue | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
    $failed++
  }
  Remove-Item -LiteralPath $prog, $errf -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("Finished. {0} converted, {1} failed." -f $saved.Count, $failed) -ForegroundColor Green
if ($saved.Count -gt 0) {
  Write-Host 'Your MP3s are here:'
  $saved | ForEach-Object { Write-Host "  $_" }
  if (-not $NoOpen) { Start-Process explorer.exe -ArgumentList "/select,`"$($saved[-1])`"" }
}
Finish
