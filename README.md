# Antigravity CLI (`agy`) Custom Statusline Guide (only for Windows powershell) 
## [한국어 readme](README.md)    
## [English readme](README_eng.md)  
Google Antigravity CLI(`agy`)의 상태 표시줄(Statusline)을 **Codex 스타일**로 커스텀 구성하고 관리하기 위한 안내 문서입니다.

---

## 1. 개요 (Overview)

Antigravity CLI의 상태 표시줄 커스텀 기능은 세션 상태가 변경될 때마다 터미널 UI(TUI)가 세션 메타데이터를 JSON 형태로 등록된 스크립트의 `stdin`으로 전달하고, 스크립트가 `stdout`으로 출력한 텍스트를 상태 표시줄 영역에 렌더링하는 방식으로 작동합니다.

### 목표 포맷 (Codex 스타일)
```text
[Gemini 3.8 Flash (High) · C:\workspace · Context 0% used · 5h 87% left · weekly 92% left]
```

---

## 2. JSON Payload 스키마 (데이터 구조)

CLI가 스크립트의 `stdin`으로 전달하는 주요 JSON 필드 구조는 다음과 같습니다:

| 필드 경로 | 타입 | 설명 |
| :--- | :--- | :--- |
| `model.display_name` | String | 활성 모델의 표시 이름 (예: `Gemini 3.8 Flash (High)`) |
| `model.id` | String | 활성 모델 ID (fallback용) |
| `workspace.current_dir` | String | 현재 작업 중인 프로젝트 디렉터리 경로 |
| `cwd` | String | CLI 실행 기준 디렉터리 |
| `context_window.used_percentage` | Number | 현재 컨텍스트 윈도우 사용률 (%) |
| `quota.<bucket-id>.remaining_fraction` | Number | 해당 쿼터 버킷의 잔여 비율 (0.0 ~ 1.0) |
| `quota.<bucket-id>.reset_time` | String | 쿼터 초기화 예정 시각 (ISO 8601) |
| `quota.<bucket-id>.reset_in_seconds` | Number | 쿼터 초기화까지 남은 시간(초) |

> [!IMPORTANT]
> `quota`는 단일 객체가 아니라 **시간 단위/모델 단위 버킷 맵(`Map<string, QuotaBucket>`)** 구조입니다.
> 5시간 롤링 한도는 `gemini-5h`, 주간 한도는 `gemini-weekly` 키에 각각 매핑되어 있습니다.

```json
{
  "model": {
    "id": "gemini-3.8-flash",
    "display_name": "Gemini 3.8 Flash (High)"
  },
  "workspace": {
    "current_dir": "C:\\workspace"
  },
  "context_window": {
    "used_percentage": 0
  },
  "quota": {
    "gemini-5h": {
      "remaining_fraction": 0.87,
      "reset_time": "2026-09-11T20:00:00Z",
      "reset_in_seconds": 18000
    },
    "gemini-weekly": {
      "remaining_fraction": 0.92,
      "reset_time": "2026-09-18T00:00:00Z",
      "reset_in_seconds": 540000
    }
  }
}
```

---

## 3. 스크립트 작성 (`statusline.ps1`)

경로: `C:\Users\i2coinslab\.gemini\antigravity-cli\statusline.ps1`

```powershell
# stdin 으로부터 CLI 세션 상태 JSON 수신
$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit }

# 디버깅이 필요할 때 아래 행의 주석을 해제하여 수신된 실제 JSON을 확인할 수 있습니다.
# $rawInput | Out-File -FilePath "$env:TEMP\agy_statusline_payload.json" -Encoding utf8

$inputJson = $rawInput | ConvertFrom-Json

# 1. 모델 표시명
$model = if ($inputJson.model.display_name) { $inputJson.model.display_name } else { $inputJson.model.id }

# 2. 작업 디렉터리
$dir = if ($inputJson.workspace.current_dir) { $inputJson.workspace.current_dir } else { $inputJson.cwd }

# 3. 컨텍스트 토큰 사용량
$ctx = if ($null -ne $inputJson.context_window.used_percentage) { [math]::Round($inputJson.context_window.used_percentage) } else { 0 }

# 4. Quota 버킷 추출 (5h 및 weekly)
$quotaParts = @()
if ($inputJson.quota) {
    # 5시간 윈도우 (gemini-5h 또는 5h)
    $fiveHourProp = $inputJson.quota.PSObject.Properties['gemini-5h']
    if (-not $fiveHourProp) { $fiveHourProp = $inputJson.quota.PSObject.Properties['5h'] }
    if ($fiveHourProp -and $null -ne $fiveHourProp.Value.remaining_fraction) {
        $pct = [math]::Round($fiveHourProp.Value.remaining_fraction * 100)
        $quotaParts += "5h $pct% left"
    }

    # 주간 윈도우 (gemini-weekly 또는 weekly)
    $weeklyProp = $inputJson.quota.PSObject.Properties['gemini-weekly']
    if (-not $weeklyProp) { $weeklyProp = $inputJson.quota.PSObject.Properties['weekly'] }
    if ($weeklyProp -and $null -ne $weeklyProp.Value.remaining_fraction) {
        $pct = [math]::Round($weeklyProp.Value.remaining_fraction * 100)
        $quotaParts += "weekly $pct% left"
    }

    # 표준 키가 존재하지 않을 때 동적 fallback
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

# 최종 상태표시줄 한 줄 출력
Write-Output "[$model · $dir · Context $ctx% used · $quotaStr]"
```

---

## 4. `settings.json` 연동 설정

[settings.json](file:///C:/Users/i2coinslab/.gemini/antigravity-cli/settings.json) 파일에 `statusLine` 블록을 추가합니다:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/i2coinslab/.gemini/antigravity-cli/statusline.ps1",
    "padding": 0,
    "enabled": true,
    "stack_with_default": false
  }
}
```

### 옵션 설명
- `command`: 실행할 스크립트 명령줄.
- `padding`: 상태표시줄 상단에 추가할 빈 줄 수 (기본값: `0`).
- `enabled`: 상태표시줄 활성화 여부 (`true` / `false`).
- `stack_with_default`: 기존 내장 상태표시줄 아래에 커스텀 줄을 추가로 띄울지 여부 (완전 대체를 원하면 `false`).

---

## 5. CLI 유용한 명령어

- `/statusline`: 상태 표시줄 on/off 토글 및 상태 바 설정 오버레이 진입
- `/quota` 또는 `/usage`: 현재 요금제의 정확한 토큰/크레딧/리셋 윈도우 상세 패널 확인
- `/config` 또는 `/settings`: 대화형 설정 패널 열기

---

## 6. 공식 문서 참고 (References)

- [Antigravity Docs Home](https://antigravity.google/docs)
- [Antigravity CLI Reference](https://antigravity.google/docs/cli/reference)
- [Antigravity CLI Features](https://antigravity.google/docs/cli/features)
