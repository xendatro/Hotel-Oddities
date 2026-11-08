param()
$ErrorActionPreference = 'Stop'
$batchRoot = $PSScriptRoot
$sources = @(Get-ChildItem -LiteralPath $batchRoot -Filter 'sources-*.json' | ForEach-Object { $items = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json; foreach ($item in $items) { $item } })
foreach ($entry in $sources) {
    $finalPath = Join-Path $batchRoot ('final/' + $entry.id + '.png')
    $previewPath = Join-Path $batchRoot ('previews/' + $entry.id + '.jpg')
    if (-not (Test-Path -LiteralPath $finalPath)) {
        & ffmpeg -hide_banner -loglevel error -i $entry.source -vf 'scale=1920:1080:flags=lanczos' -frames:v 1 -update 1 $finalPath
        if ($LASTEXITCODE -ne 0) { throw ('Export failed: ' + $entry.id) }
    }
    if (-not (Test-Path -LiteralPath $previewPath)) {
        & ffmpeg -hide_banner -loglevel error -i $finalPath -vf 'scale=480:270:flags=lanczos' -frames:v 1 -q:v 3 -update 1 $previewPath
        if ($LASTEXITCODE -ne 0) { throw ('Preview failed: ' + $entry.id) }
    }
}
Write-Output ('Exported ' + $sources.Count + ' thumbnails')
