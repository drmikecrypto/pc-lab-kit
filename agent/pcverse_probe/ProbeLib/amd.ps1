. "$PSScriptRoot\common.ps1"

function Get-ProbeAmdGpuTelemetry {
    $rocm = Get-Command rocm-smi -ErrorAction SilentlyContinue
    if (-not $rocm) {
        return @{ available = $false }
    }

    try {
        $cards = @()
        $jsonOut = & rocm-smi --showuse --showtemp --showpower --showclocks --showmeminfo vram --showproductname --json 2>$null
        if ($jsonOut) {
            $parsed = $jsonOut | ConvertFrom-Json
            return @{ available = $true; raw_json = $parsed; source = 'rocm-smi' }
        }

        $text = & rocm-smi 2>$null
        return @{ available = $true; raw_text = ($text -join "`n"), source = 'rocm-smi' }
    } catch {
        return @{ available = $false; error = $_.Exception.Message }
    }
}
