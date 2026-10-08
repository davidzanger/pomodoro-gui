param(
  [string]$LcovPath = "coverage/lcov.info",
  [ValidateRange(0, 100)]
  [double]$MinimumCoverage = 95
)

if (-not (Test-Path -LiteralPath $LcovPath -PathType Leaf)) {
  throw "Coverage report not found: $LcovPath. Run 'flutter test --coverage' first."
}

$coveredLines = 0
$totalLines = 0
$fileCovered = 0
$fileTotal = 0
$sourceFile = $null

foreach ($line in Get-Content -LiteralPath $LcovPath) {
  if ($line.StartsWith("SF:")) {
    $sourceFile = $line.Substring(3).Replace("\", "/")
    $fileCovered = 0
    $fileTotal = 0
    continue
  }

  if ($line.StartsWith("DA:") -and
      $sourceFile -match "^lib/" -and
      $sourceFile -notmatch "^lib/src/rust/") {
    $hitCount = [int]($line.Substring(3).Split(",")[1])
    $fileTotal++
    $totalLines++
    if ($hitCount -gt 0) {
      $fileCovered++
      $coveredLines++
    }
    continue
  }

  if ($line -eq "end_of_record" -and
      $sourceFile -match "^lib/" -and
      $sourceFile -notmatch "^lib/src/rust/") {
    if ($fileTotal -gt 0) {
      $filePercentage = 100 * $fileCovered / $fileTotal
      "{0,6:N2}% ({1}/{2}) {3}" -f $filePercentage, $fileCovered, $fileTotal, $sourceFile
    }
    $sourceFile = $null
  }
}

if ($totalLines -eq 0) {
  throw "No hand-written Dart source lines found in $LcovPath."
}

$percentage = 100 * $coveredLines / $totalLines
"Total: {0:N2}% ({1}/{2}) hand-written Dart lines." -f $percentage, $coveredLines, $totalLines
if ($percentage -le $MinimumCoverage) {
  throw "Coverage must exceed $MinimumCoverage%; measured $($percentage.ToString('N2'))%."
}
