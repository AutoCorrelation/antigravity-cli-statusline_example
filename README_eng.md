# Antigravity CLI (`agy`) Custom Statusline Guide (only for Windows PowerShell)
[한국어 readme](!README.md)
[English readme](!README_eng.md)

This is a guide document for custom-configuring and managing the statusline of the Google Antigravity CLI (`agy`) in a **Codex style**.

---

## 1. Overview

The Antigravity CLI statusline custom feature works by having the terminal UI (TUI) pass session metadata in JSON format to the `stdin` of a registered script whenever the session state changes, and then rendering the text output by the script to `stdout` in the statusline area.

### Target Format (Codex Style)

```text
[Gemini 3.8 Flash (High) · C:\workspace · Context 0% used · 5h 87% left · weekly 92% left]

```

---

## 2. JSON Payload Schema (Data Structure)

The main JSON field structures passed by the CLI to the script's `stdin` are as follows:

| Field Path | Type | Description |
| --- | --- | --- |
| `model.display_name` | String | Display name of the active model (e.g., `Gemini 3.8 Flash (High)`) |
| `model.id` | String | Active model ID (for fallback) |
| `workspace.current_dir` | String | Current working project directory path |
| `cwd` | String | CLI execution baseline directory |
| `context_window.used_percentage` | Number | Current context window usage rate (%) |
| `quota.<bucket-id>.remaining_fraction` | Number | Remaining fraction of the corresponding quota bucket (0.0 ~ 1.0) |
| `quota.<bucket-id>.reset_time` | String | Expected quota reset time (ISO 8601) |
| `quota.<bucket-id>.reset_in_seconds` | Number | Time remaining until quota reset in seconds |

> [!IMPORTANT]
> `quota` is not a single object, but rather a **time-unit/model-unit bucket map (`Map<string, QuotaBucket>`)** structure.
> The 5-hour rolling limit is mapped to the `gemini-5h` key, and the weekly limit is mapped to the `gemini-weekly` key.

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

## 3. Writing the Script (`statusline.ps1`)

Path: `C:\Users\i2coinslab\.gemini\antigravity-cli\statusline.ps1`

```powershell
# Receive CLI session status JSON from stdin
$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit }

# When debugging is needed, uncomment the line below to check the actual received JSON.
# $rawInput | Out-File -FilePath "$env:TEMP\agy_statusline_payload.json" -Encoding utf8

$inputJson = $rawInput | ConvertFrom-Json

# 1. Model display name
$model = if ($inputJson.model.display_name) { $inputJson.model.display_name } else { $inputJson.model.id }

# 2. Working directory
$dir = if ($inputJson.workspace.current_dir) { $inputJson.workspace.current_dir } else { $inputJson.cwd }

# 3. Context token usage
$ctx = if ($null -ne $inputJson.context_window.used_percentage) { [math]::Round($inputJson.context_window.used_percentage) } else { 0 }

# 4. Extract Quota buckets (5h and weekly)
$quotaParts = @()
if ($inputJson.quota) {
    # 5-hour window (gemini-5h or 5h)
    $fiveHourProp = $inputJson.quota.PSObject.Properties['gemini-5h']
    if (-not $fiveHourProp) { $fiveHourProp = $inputJson.quota.PSObject.Properties['5h'] }
    if ($fiveHourProp -and $null -ne $fiveHourProp.Value.remaining_fraction) {
        $pct = [math]::Round($fiveHourProp.Value.remaining_fraction * 100)
        $quotaParts += "5h $pct% left"
    }

    # Weekly window (gemini-weekly or weekly)
    $weeklyProp = $inputJson.quota.PSObject.Properties['gemini-weekly']
    if (-not $weeklyProp) { $weeklyProp = $inputJson.quota.PSObject.Properties['weekly'] }
    if ($weeklyProp -and $null -ne $weeklyProp.Value.remaining_fraction) {
        $pct = [math]::Round($weeklyProp.Value.remaining_fraction * 100)
        $quotaParts += "weekly $pct% left"
    }

    # Dynamic fallback when standard keys do not exist
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

# Output final statusline single line
Write-Output "[$model · $dir · Context $ctx% used · $quotaStr]"

```

---

## 4. `settings.json` Integration Setup

Add the `statusLine` block to the settings.json file:

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

### Option Descriptions

* `command`: Command line of the script to execute.
* `padding`: Number of blank lines to add at the top of the statusline (default: `0`).
* `enabled`: Whether to enable the statusline (`true` / `false`).
* `stack_with_default`: Whether to stack the custom line below the existing built-in statusline (`false` if you want a complete replacement).

---

## 5. Useful CLI Commands

* `/statusline`: Toggle statusline on/off and enter the status bar settings overlay
* `/quota` or `/usage`: Check the detailed panel of current plan's exact token/credit/reset window
* `/config` or `/settings`: Open the interactive settings panel

---

## 6. References

* [Antigravity Docs Home](https://antigravity.google/docs)
* [Antigravity CLI Reference](https://antigravity.google/docs/cli/reference)
* [Antigravity CLI Features](https://antigravity.google/docs/cli/features)
