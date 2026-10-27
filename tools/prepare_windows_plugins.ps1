$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$linkRoot = Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $linkRoot | Out-Null
foreach ($plugin in $manifest.plugins.windows) {
    if ($plugin.name -notmatch '^[a-zA-Z0-9_]+$') { throw 'Invalid plugin name.' }
    $link = Join-Path $linkRoot $plugin.name
    if (-not (Test-Path -LiteralPath $link)) {
        # NTFS directory junctions work without the Windows Developer Mode setting.
        New-Item -ItemType Junction -Path $link -Target $plugin.path | Out-Null
    }
}
Write-Output 'Windows plugin links are ready.'
