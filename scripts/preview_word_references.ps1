param([string[]]$Variants = @('python-experiment','cad-report','course-paper','electronic-senses'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$previewRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'build/word-reference-review'))
New-Item -ItemType Directory -Force -Path $previewRoot | Out-Null
foreach ($variant in $Variants) {
    $auditPath = [string](Resolve-Path -LiteralPath (Join-Path $root "styles/word/$variant/reference-reviewed.docx")).Path
    $pdfPath = [string][System.IO.Path]::GetFullPath((Join-Path $previewRoot "$variant.pdf"))
    $auditWord = New-Object -ComObject Word.Application
    $auditDoc = $null
    try {
        Write-Output "Opening $auditPath"
        $auditDoc = $auditWord.Documents.Open($auditPath, $false, $true)
        Write-Output "Exporting $variant"
        $auditDoc.ExportAsFixedFormat($pdfPath, 17)
        Write-Output "$variant : $($auditDoc.ComputeStatistics(2)) pages"
    } finally {
        if ($null -ne $auditDoc) { $auditDoc.Close(0) }
        $auditWord.Quit()
    }
}
