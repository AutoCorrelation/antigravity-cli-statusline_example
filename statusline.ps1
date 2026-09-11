$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit }

# (선택 사항) 실제 수신되는 JSON 구조를 직접 확인하고 싶다면 아래 주석을 해제하세요.
# $rawInput | Out-File -FilePath "$env:TEMP\agy_statusline_payload.json" -Encoding utf8

$inputJson = $rawInput | ConvertFrom-Json

# 1. 모델명 추출
$model = if ($inputJson.model.display_name) { $inputJson.model.display_name } else { $inputJson.model.id }

# 2. 작업 디렉터리 추출
$dir = if ($inputJson.workspace.current_dir) { $inputJson.workspace.current_dir } else { $inputJson.cwd }

# 3. 컨텍스트 토큰 사용률 추출
$ctx = if ($null -ne $inputJson.context_window.used_percentage) { [math]::Round($inputJson.context_window.used_percentage) } else { 0 }

# 4. Quota 버킷별 잔여량 추출 (5h / weekly)
$quotaParts = @()
if ($inputJson.quota) {
    # 5시간 윈도우 버킷 (gemini-5h 또는 5h)
    $fiveHourProp = $inputJson.quota.PSObject.Properties['gemini-5h']
    if (-not $fiveHourProp) { $fiveHourProp = $inputJson.quota.PSObject.Properties['5h'] }
    if ($fiveHourProp -and $null -ne $fiveHourProp.Value.remaining_fraction) {
        $pct = [math]::Round($fiveHourProp.Value.remaining_fraction * 100)
        $quotaParts += "5h $pct% left"
    }

    # 주간 윈도우 버킷 (gemini-weekly 또는 weekly)
    $weeklyProp = $inputJson.quota.PSObject.Properties['gemini-weekly']
    if (-not $weeklyProp) { $weeklyProp = $inputJson.quota.PSObject.Properties['weekly'] }
    if ($weeklyProp -and $null -ne $weeklyProp.Value.remaining_fraction) {
        $pct = [math]::Round($weeklyProp.Value.remaining_fraction * 100)
        $quotaParts += "weekly $pct% left"
    }

    # 표준 키가 아닐 경우: quota 내 모든 버킷 동적 탐색
    if ($quotaParts.Count -eq 0) {
        if ($null -ne $inputJson.quota.remaining_fraction) {
            $pct = [math]::Round($inputJson.quota.remaining_fraction * 100)
            $quotaParts += "$pct% left"
        } else {
            foreach ($prop in $inputJson.quota.PSObject.Properties) {
                if ($prop.Value -and $null -ne $prop.Value.remaining_fraction) {
                    $pct = [math]::Round($prop.Value.remaining_fraction * 100)
                    $cleanName = $prop.Name -replace '^gemini-', ''
                    $quotaParts += "$cleanName $pct% left"
                }
            }
        }
    }
}

$quotaStr = if ($quotaParts.Count -gt 0) { $quotaParts -join ' · ' } else { "quota 100% left" }

Write-Output "[$model · $dir · Context $ctx% used · $quotaStr]"