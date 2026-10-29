param([switch]$TemplatesOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    if (-not $TemplatesOnly) {
        $papers = Get-ChildItem -LiteralPath $projectRoot -Directory -Filter 'arXiv-*'
        foreach ($paper in $papers) {
            $entry = Join-Path $paper.FullName 'report.qmd'
            if (Test-Path -LiteralPath $entry) {
                & quarto render $entry --to docx
                if ($LASTEXITCODE -ne 0) { throw "Word build failed: $entry" }
            }
        }
    } else {
        & quarto render arXiv-2508.00362v1/report.qmd --to docx
        if ($LASTEXITCODE -ne 0) { throw 'Word template build failed: neu-journal' }
    }
    foreach ($entry in @('report-modern','report-classic','report-bachelor')) {
        & quarto render "arXiv-2508.00362v1/$entry.qmd" --to docx
        if ($LASTEXITCODE -ne 0) { throw "Word template build failed: $entry" }
    }
} finally { Pop-Location }
