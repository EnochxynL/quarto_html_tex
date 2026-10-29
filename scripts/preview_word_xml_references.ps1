$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$records = Get-Content -LiteralPath (Join-Path $root 'styles/word/xml-validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($record in $records) {
    $folder = Join-Path $root "build/word-xml-review/$($record.name)"
    foreach ($kind in @('original', 'reference', 'pandoc-probe')) {
        $inputPath = switch ($kind) {
            'original' { $record.source }
            'reference' { Join-Path $root $record.reference }
            'pandoc-probe' { Join-Path $folder 'pandoc-probe.docx' }
        }
        $inputPath = [string](Resolve-Path -LiteralPath $inputPath).Path
        $pdfPath = [string][System.IO.Path]::GetFullPath((Join-Path $folder "$kind.pdf"))
        $auditWord = New-Object -ComObject Word.Application
        $auditDoc = $null
        try {
            Write-Output "Opening $($record.name) / $kind"
            $auditDoc = $auditWord.Documents.Open($inputPath, $false, $true)
            $auditDoc.ExportAsFixedFormat($pdfPath, 17)
            Write-Output "$($record.name) / $kind : $($auditDoc.ComputeStatistics(2)) pages"
        } finally {
            if ($null -ne $auditDoc) { $auditDoc.Close(0) }
            $auditWord.Quit()
        }
    }
}
