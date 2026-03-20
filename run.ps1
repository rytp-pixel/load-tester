param(
  [string]$ConfigPath = "",
  [switch]$NoPrompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Directory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Parse-Headers([string]$HeaderInput) {
  $headers = @{}
  if ([string]::IsNullOrWhiteSpace($HeaderInput)) {
    return $headers
  }

  $pairs = $HeaderInput.Split(",")
  foreach ($pair in $pairs) {
    $trimmedPair = $pair.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedPair)) {
      continue
    }
    $parts = $trimmedPair.Split(":", 2)
    if ($parts.Count -ne 2) {
      throw "Invalid header pair: '$trimmedPair'. Use format Key:Value,Key2:Value2"
    }
    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    if ([string]::IsNullOrWhiteSpace($key)) {
      throw "Header name cannot be empty in pair '$trimmedPair'"
    }
    $headers[$key] = $value
  }

  return $headers
}

function Build-InteractiveConfig {
  Write-Host ""
  Write-Host "Interactive k6 config wizard"
  Write-Host "----------------------------"

  $testName = Read-Host "Test name (default: blackbox-http-test)"
  if ([string]::IsNullOrWhiteSpace($testName)) { $testName = "blackbox-http-test" }

  $baseUrl = Read-Host "Base URL (example: https://example.com)"
  if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    throw "Base URL is required."
  }

  $pathsInput = Read-Host "Comma-separated endpoint paths/URLs (example: /,/health,https://example.com/api)"
  if ([string]::IsNullOrWhiteSpace($pathsInput)) {
    throw "At least one endpoint path/URL is required."
  }
  $paths = $pathsInput.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  if ($paths.Count -eq 0) {
    throw "At least one valid endpoint path/URL is required."
  }

  $headersInput = Read-Host "Headers Key:Value comma-separated (optional)"
  $headers = Parse-Headers $headersInput

  $stageTargetsInput = Read-Host "Ramp targets by VU comma-separated (default: 10,50,150,0)"
  if ([string]::IsNullOrWhiteSpace($stageTargetsInput)) { $stageTargetsInput = "10,50,150,0" }
  $targets = $stageTargetsInput.Split(",") | ForEach-Object { [int]$_.Trim() }

  $stageDurationInput = Read-Host "Stage duration each step (default: 1m)"
  if ([string]::IsNullOrWhiteSpace($stageDurationInput)) { $stageDurationInput = "1m" }

  $p95Limit = Read-Host "p95 limit ms for threshold (default: 1200)"
  if ([string]::IsNullOrWhiteSpace($p95Limit)) { $p95Limit = "1200" }
  $p99Limit = Read-Host "p99 limit ms for threshold (default: 2000)"
  if ([string]::IsNullOrWhiteSpace($p99Limit)) { $p99Limit = "2000" }
  $errorRateLimit = Read-Host "Max error rate (default: 0.02)"
  if ([string]::IsNullOrWhiteSpace($errorRateLimit)) { $errorRateLimit = "0.02" }

  $endpoints = @()
  foreach ($path in $paths) {
    $safeName = $path.Replace("/", "_").Replace(":", "_")
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "root" }
    $endpoints += @{
      name = $safeName
      method = "GET"
      url = $path
      weight = 1
      expectedStatus = @(200)
    }
  }

  $stages = @()
  foreach ($target in $targets) {
    $stages += @{
      duration = $stageDurationInput
      target = $target
    }
  }

  return @{
    testName = $testName
    baseUrl = $baseUrl
    headers = $headers
    timeout = "30s"
    sleepSeconds = 0
    discardResponseBodies = $true
    summaryTrendStats = @("avg", "min", "med", "max", "p(90)", "p(95)", "p(99)")
    stages = $stages
    thresholds = @{
      http_req_failed = @("rate<$errorRateLimit")
      http_req_duration = @("p(95)<$p95Limit", "p(99)<$p99Limit")
      successful_checks = @("rate>0.98")
    }
    endpoints = $endpoints
  }
}

function Get-Metric([object]$Summary, [string]$MetricName, [string]$ValueName) {
  if (-not $Summary.metrics.$MetricName) { return $null }
  if (-not $Summary.metrics.$MetricName.values) { return $null }
  $values = $Summary.metrics.$MetricName.values
  if (-not $values.PSObject.Properties.Name.Contains($ValueName)) { return $null }
  return $values.$ValueName
}

function Generate-MarkdownReport([string]$SummaryPath, [string]$ConfigPath, [string]$OutputPath) {
  $summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json
  $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

  $httpReqs = Get-Metric $summary "http_reqs" "count"
  $httpFailedRate = Get-Metric $summary "http_req_failed" "rate"
  $httpDurationAvg = Get-Metric $summary "http_req_duration" "avg"
  $httpDurationP95 = Get-Metric $summary "http_req_duration" "p(95)"
  $httpDurationP99 = Get-Metric $summary "http_req_duration" "p(99)"
  $checksRate = Get-Metric $summary "checks" "rate"
  $vusMax = Get-Metric $summary "vus_max" "value"
  $iterations = Get-Metric $summary "iterations" "count"

  $thresholdLines = @()
  foreach ($metric in $summary.metrics.PSObject.Properties.Name) {
    $metricObject = $summary.metrics.$metric
    if ($metricObject.thresholds) {
      foreach ($thr in $metricObject.thresholds.PSObject.Properties.Name) {
        $ok = $metricObject.thresholds.$thr.ok
        $status = if ($ok) { "PASS" } else { "FAIL" }
        $thresholdLines += "- $metric :: $thr => $status"
      }
    }
  }

  $endpointLines = @()
  foreach ($ep in $config.endpoints) {
    $endpointLines += "- $($ep.method) $($ep.url)"
  }

  $stagesLines = @()
  foreach ($stage in $config.stages) {
    $stagesLines += "- duration=$($stage.duration), target=$($stage.target)"
  }

  $headersLines = @()
  foreach ($headerName in $config.headers.PSObject.Properties.Name) {
    $headersLines += "- $headerName: $($config.headers.$headerName)"
  }
  if ($headersLines.Count -eq 0) {
    $headersLines += "- (no custom headers)"
  }

  $content = @(
    "# k6 Load Test Report"
    ""
    "## Test info"
    "- name: $($config.testName)"
    "- generated_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")"
    "- base_url: $($config.baseUrl)"
    ""
    "## Endpoints"
    $endpointLines
    ""
    "## Headers"
    $headersLines
    ""
    "## Ramp stages"
    $stagesLines
    ""
    "## Key metrics"
    "- http requests: $httpReqs"
    "- iterations: $iterations"
    "- max vus: $vusMax"
    "- failed request rate: $httpFailedRate"
    "- checks pass rate: $checksRate"
    "- latency avg (ms): $httpDurationAvg"
    "- latency p95 (ms): $httpDurationP95"
    "- latency p99 (ms): $httpDurationP99"
    ""
    "## Threshold results"
    $thresholdLines
    ""
    "## Artifacts"
    "- summary json: $(Split-Path $SummaryPath -Leaf)"
    "- raw stream json: raw.json"
    "- dashboard html: dashboard.html"
  ) -join "`r`n"

  Set-Content -LiteralPath $OutputPath -Value $content -Encoding UTF8
}

Ensure-Directory ".\k6"
Ensure-Directory ".\reports"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker is required. Install Docker Desktop and try again."
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  if ($NoPrompt) {
    if (Test-Path -LiteralPath ".\k6\config.json") {
      $ConfigPath = ".\k6\config.json"
    } elseif (Test-Path -LiteralPath ".\k6\config.example.json") {
      $ConfigPath = ".\k6\config.example.json"
    } else {
      throw "No config file found. Provide -ConfigPath or run without -NoPrompt."
    }
  } else {
    $interactiveConfig = Build-InteractiveConfig
    $ConfigPath = ".\k6\config.generated.json"
    ($interactiveConfig | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Write-Host "Generated config: $ConfigPath"
  }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  throw "Config file not found: $ConfigPath"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = ".\reports\$stamp"
Ensure-Directory $reportDir

$projectPath = (Resolve-Path ".").Path
$dockerWorkPath = "/work"
$dockerConfigPath = "$dockerWorkPath/" + (($ConfigPath -replace "\\", "/").TrimStart(".","/"))
$summaryPath = "$reportDir\summary.json"
$rawPath = "$reportDir\raw.json"
$markdownPath = "$reportDir\report.md"
$dashboardPath = "$reportDir\dashboard.html"

$dockerSummaryPath = "$dockerWorkPath/" + (($summaryPath -replace "\\", "/").TrimStart(".","/"))
$dockerRawPath = "$dockerWorkPath/" + (($rawPath -replace "\\", "/").TrimStart(".","/"))
$dockerDashboardPath = "$dockerWorkPath/" + (($dashboardPath -replace "\\", "/").TrimStart(".","/"))

Write-Host ""
Write-Host "Starting test..."
Write-Host "Real-time dashboard: http://localhost:5665"
Write-Host "Config file: $ConfigPath"
Write-Host "Report dir: $reportDir"
Write-Host ""

docker run --rm -i `
  -p 5665:5665 `
  -v "${projectPath}:${dockerWorkPath}" `
  -w "${dockerWorkPath}" `
  -e "CONFIG_PATH=$dockerConfigPath" `
  -e "K6_WEB_DASHBOARD=true" `
  -e "K6_WEB_DASHBOARD_EXPORT=$dockerDashboardPath" `
  grafana/k6:latest run `
  "$dockerWorkPath/k6/scenario.js" `
  --summary-export "$dockerSummaryPath" `
  --out "json=$dockerRawPath"

if (-not (Test-Path -LiteralPath $summaryPath)) {
  throw "Summary file not generated: $summaryPath"
}

Generate-MarkdownReport -SummaryPath $summaryPath -ConfigPath $ConfigPath -OutputPath $markdownPath

Write-Host ""
Write-Host "Done. Reports:"
Write-Host "- Summary JSON: $summaryPath"
Write-Host "- Raw JSON:     $rawPath"
Write-Host "- Dashboard:    $dashboardPath"
Write-Host "- Markdown:     $markdownPath"

