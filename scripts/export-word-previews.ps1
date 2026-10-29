param([string[]]$Documents, [int]$SamplePages = 0)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Documents) {
    $Documents = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'build') -Recurse -Filter 'report*.docx' |
        Where-Object { $_.Name -in @('report.docx','report-modern.docx','report-classic.docx','report-bachelor.docx') } |
        ForEach-Object { $_.FullName })
    $fixture = Join-Path $projectRoot 'build/tests/docx-tex/fixture.docx'
    if (Test-Path -LiteralPath $fixture) { $Documents += $fixture }
}
$reviewApp = New-Object -ComObject Word.Application
try {
    foreach ($path in $Documents) {
        $reviewDocument = $null
        try {
            $resolved = (Resolve-Path -LiteralPath $path).Path
            $suffix = if ($SamplePages -gt 0) { '-sample-preview.pdf' } else { '-preview.pdf' }
            $destination = Join-Path (Split-Path -Parent $resolved) ([System.IO.Path]::GetFileNameWithoutExtension($resolved) + $suffix)
            Write-Output "Opening: $resolved"
            $reviewDocument = $reviewApp.Documents.OpenNoRepairDialog([string]$resolved, $false, $true)
            $pageCount = if ($SamplePages -gt 0) { $SamplePages } else { $reviewDocument.ComputeStatistics(2) }
            Write-Output "Exporting pages 1-$pageCount"
            # Review PDFs use screen optimization; publication PDFs remain the
            # separate native LaTeX output. An explicit full-page range avoids
            # the local Word build's long wait with its default AllDocument mode.
            $reviewDocument.ExportAsFixedFormat([string]$destination, 17, $false, 1, 3, 1, [int]$pageCount)
            Write-Output "$destination ($pageCount pages)"
        } finally {
            if ($null -ne $reviewDocument) { $reviewDocument.Close(0) }
        }
    }
} finally { $reviewApp.Quit() }
