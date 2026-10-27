param([int]$Seconds = 30)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$releaseDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$executable = Join-Path $releaseDir 'plastic_memory.exe'
$qaDir = Join-Path $projectRoot 'build\qa\flow'
New-Item -ItemType Directory -Force -Path $qaDir | Out-Null
$appProcess = Start-Process -FilePath $executable -WorkingDirectory $releaseDir -WindowStyle Hidden -PassThru
try {
    Start-Sleep -Seconds 5
    $appProcess.Refresh()
    if ($appProcess.HasExited) { throw 'The application exited before profiling.' }
    $cpuStart = $appProcess.TotalProcessorTime.TotalSeconds
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds $Seconds
    $appProcess.Refresh()
    $timer.Stop()
    $cpuSeconds = $appProcess.TotalProcessorTime.TotalSeconds - $cpuStart
    $logicalProcessors = [Environment]::ProcessorCount
    $result = [ordered]@{
        measuredAt = [DateTimeOffset]::Now.ToString('o')
        build = 'Windows release'
        elapsedSeconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        processCpuSeconds = [Math]::Round($cpuSeconds, 4)
        logicalProcessors = $logicalProcessors
        cpuPercentOfMachine = [Math]::Round(100 * $cpuSeconds / $timer.Elapsed.TotalSeconds / $logicalProcessors, 3)
        cpuPercentOfOneCore = [Math]::Round(100 * $cpuSeconds / $timer.Elapsed.TotalSeconds, 3)
        peakWorkingSetMB = [Math]::Round($appProcess.PeakWorkingSet64 / 1MB, 1)
    }
    $json = $result | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $qaDir 'performance.json') -Value $json -Encoding utf8
    Write-Output $json
} finally {
    $appProcess.Refresh()
    if (-not $appProcess.HasExited) {
        $null = $appProcess.CloseMainWindow()
        $null = $appProcess.WaitForExit(5000)
    }
    $appProcess.Dispose()
}
