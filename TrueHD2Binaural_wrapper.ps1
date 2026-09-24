param (
    [Parameter(Mandatory=$false)]
    [string]$FilePath = "",

    [Parameter(Mandatory=$false)]
    [string]$MpvPath = "mpv",

    [Parameter(Mandatory=$false)]
    [switch]$KeepTemp
)

$originalLocation = Get-Location

# 1. Ciclo while per il file di input (supporta vari formati)
while ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath -ErrorAction SilentlyContinue)) {
	if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
        Write-Host "[WARN] File not found: '$FilePath'" -ForegroundColor Yellow
    }
    $FilePath = Read-Host "Enter the media file path (e.g., .mkv, .m2ts) or type 'e' to exit"
    
    if ($FilePath.Trim().ToLower() -eq 'e') {
        Write-Host "Scrip ended" -ForegroundColor Red
        exit
    }
    
    $FilePath = $FilePath -replace '^"|"$', ''
}

# 2. Controllo dipendenze con suggerimento Winget
if (-not (Get-Command "ffmpeg" -ErrorAction SilentlyContinue) -or -not (Get-Command "ffprobe" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] ffmpeg or ffprobe not found in system PATH." -ForegroundColor Red
    Write-Host "[INFO] You can easily install them by running: winget install ffmpeg" -ForegroundColor Cyan
    exit
}

# 3. Ciclo while interattivo per la build portable di MPV
while ([string]::IsNullOrWhiteSpace($MpvPath) -or (-not (Get-Command $MpvPath -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $MpvPath -ErrorAction SilentlyContinue))) {
	Write-Host "[WARN] MPV not found at '$MpvPath' or in system PATH." -ForegroundColor Yellow
    $MpvPath = Read-Host "Enter the full path to mpv.exe (e.g., C:\Tools\mpv.exe) or type 'e' to exit"
    
    if ($MpvPath.Trim().ToLower() -eq 'e') {
        Write-Host "Scrip ended" -ForegroundColor Red
        exit
    }
    
    $MpvPath = $MpvPath -replace '^"|"$', ''
}


# 1. PERCORSI ASSOLUTI (Previene file non trovati in background)
$resolvedPath = (Resolve-Path -LiteralPath $FilePath).Path
$dirName = [System.IO.Path]::GetDirectoryName($resolvedPath)
$fileName = [System.IO.Path]::GetFileName($resolvedPath)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

Set-Location -LiteralPath $dirName

$tempMka  = Join-Path $dirName "$baseName-temp.mka"
$tempWav  = Join-Path $dirName "$baseName-temp.wav"
$outputMkv = Join-Path $dirName "$baseName (with Binaural).mkv"
$logFile  = Join-Path $dirName "mpv_debug.log"

Write-Host "[INFO] The final output will be muxed into an mkv file named: '$baseName (with Binaural).mkv'" -ForegroundColor Cyan

Write-Host ""

Write-Host "1. Searching TrueHD track..." -ForegroundColor Cyan
$streams = ffprobe -v error -select_streams a -show_entries stream=index,codec_name,sample_rate -of csv=p=0 "$resolvedPath"
$truehdStream = $streams | Where-Object {$_ -match "truehd" } | Select-Object -First 1

if (-not $truehdStream) {
    Write-Host "No TrueHD track found in the file. Script ended." -ForegroundColor Red
    exit
}

$trackData =$truehdStream.Split(',')
$trackIndex =$trackData[0].Trim()

$sampleRate = 48000
if ($trackData.Count -ge 3 -and $trackData[2].Trim() -match '^\d+$') {
    $sampleRate = [int]$trackData[2].Trim()
}

$audioCount = @($streams).Count
Write-Host "TrueHD track found at index $trackIndex ($sampleRate Hz). Total number of audio tracks found: $audioCount."

Write-Host "2. Remuxing the track in a temporary .mka file..." -ForegroundColor Cyan
ffmpeg -y -v error -stats -i "$resolvedPath" -map 0:$trackIndex -c copy "$tempMka"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Critical error: FFmpeg failed the extraction of the audio track." -ForegroundColor Red
    exit
}

Write-Host "3. Rendering of the spatial binaural track (using mpv.exe)..." -ForegroundColor Cyan

# .Trim() per evitare ritorni a capo invisibili
$durationStr = (ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$resolvedPath").Trim()
$totalSeconds = 0

if ($durationStr -match '^\d+(\.\d+)?$') {
    try {
        $totalSeconds = [double]::Parse($durationStr, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        $totalSeconds = 0
    }
}

# Forzando audio-channels=stereo, Omniphony emette il 2.0 finale bit-perfect
$bytesPerSecond = $sampleRate * 2 * 4
$expectedWavSize = $totalSeconds * $bytesPerSecond

# AGGIUNTO --audio-channels=stereo per forzare il downmix binaurale a monte
$mpvArgs = "`"$tempMka`" --vid=no --vo=null --ad=orender --audio-channels=stereo --audio-format=s32 --ao=pcm --ao-pcm-file=`"$tempWav`" --log-file=`"$logFile`""

$mpvProcess = Start-Process -FilePath $MpvPath -ArgumentList $mpvArgs -NoNewWindow -PassThru -WorkingDirectory $dirName

$startTime = [datetime]::Now

while (-not $mpvProcess.HasExited) {
	$currentSize = 0
    if (Test-Path -LiteralPath $tempWav) {
        $fileInfo = New-Object System.IO.FileInfo($tempWav)
        try {
            $currentSize =$fileInfo.Length
        } catch {
            $currentSize = 0
        }
    }

    if ($currentSize -gt 0) {
        if ($expectedWavSize -gt 0) {$percentComplete = [math]::Round(($currentSize / $expectedWavSize) * 100)
            $percentComplete = [math]::Min(99, [math]::Max(0, [int]$percentComplete))

            $currentTime = [datetime]::Now
			$elapsed = $currentTime - $startTime
            $elapsedStr = "{0:D2}h {1:D2}m {2:D2}s" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds
            
            if ($elapsed.TotalSeconds -gt 8 -and $currentSize -gt 0) { $globalSpeed = $currentSize / $elapsed.TotalSeconds
                
                $secRemaining = ($expectedWavSize - $currentSize) / $globalSpeed
                if ($secRemaining -lt 0) { $secRemaining = 0 }
                
                $ts = [TimeSpan]::FromSeconds($secRemaining)
                $timeStr = "{0:D2}h {1:D2}m {2:D2}s" -f $ts.Hours, $ts.Minutes, $ts.Seconds
            } else {
                $timeStr = "Calculating..."
            }

            $currMB = [math]::Round($currentSize / 1MB, 2)
            $expMB = [math]::Round($expectedWavSize / 1MB, 2)

            Write-Progress -Activity "Rendering ($sampleRate Hz - Binaural Stereo)..." -Status "Progress: $percentComplete% | Written: $currMB MB / $expMB MB | Time left: $timeStr | Total time: $elapsedStr" -PercentComplete $percentComplete

        } else {
            $mb = [math]::Round($currentSize / 1MB, 2)
            Write-Progress -Activity "Rendering..." -Status "Writing... Current size: $mb MB" -PercentComplete 0
        }
    } else {
        Write-Progress -Activity "Rendering..." -Status "Starting rendering process..." -PercentComplete 0
    }
    
    Start-Sleep -Seconds 2
}
Write-Progress -Activity "Rendering..." -Completed

$mpvProcess.WaitForExit()
$exitCode = $mpvProcess.ExitCode

if ($null -ne $exitCode -and $exitCode -ne 0) {
    Write-Host "Critical error: MPV audio rendering failed (Exit Code: $exitCode)." -ForegroundColor Red
    if (Test-Path -LiteralPath $logFile) {
        Write-Host "--- MPV ERROR LOG (Last 15 lines) ---" -ForegroundColor Yellow
        Get-Content -LiteralPath $logFile -Tail 15 | Write-Host -ForegroundColor Yellow
    }
    if (-not $KeepTemp) {
        Remove-Item -LiteralPath $tempMka -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempWav -ErrorAction SilentlyContinue
    }
    exit
}

Remove-Item -LiteralPath $logFile -ErrorAction SilentlyContinue

Write-Host "4. Muxing into the new MKV container (Encoding to 24-bit FLAC)..." -ForegroundColor Cyan
ffmpeg -y -v error -stats -i "$resolvedPath" -ignore_length 1 -i "$tempWav" -map 0 -map 1:a -c copy -c:a:$audioCount flac -sample_fmt:a:$audioCount s32 -metadata:s:a:$audioCount "title=Dolby Atmos Binaural" "$outputMkv"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Critical error: FFmpeg final muxing failed." -ForegroundColor Red
    if (-not $KeepTemp) {
        Remove-Item -LiteralPath $tempMka -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempWav -ErrorAction SilentlyContinue
    }
    exit
}

if (-not $KeepTemp) {
    Write-Host "5. Cleaning up temporary files..." -ForegroundColor Cyan
    Remove-Item -LiteralPath $tempMka -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempWav -ErrorAction SilentlyContinue
} else {
    Write-Host "5. -KeepTemp active: temporary files retained." -ForegroundColor Yellow
}

Write-Host "Process successfully completed: $outputMkv" -ForegroundColor Green

Set-Location -LiteralPath $originalLocation.Path