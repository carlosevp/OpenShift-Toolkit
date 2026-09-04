function Write-OcpLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Verbose', 'Information', 'Warning', 'Error', 'Audit')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [hashtable]$Data,
        [string]$OperationId
    )

    $safeMessage = Protect-OcpSensitiveValue -Text $Message
    $safeData = $null
    if ($Data) {
        $json = $Data | ConvertTo-Json -Compress -Depth 8
        $safeData = Protect-OcpSensitiveValue -Text $json
    }

    $record = [ordered]@{
        timestamp     = [DateTime]::UtcNow.ToString('o')
        level         = $Level
        message       = $safeMessage
        operationId   = $OperationId
        executionMode = Get-OcpExecutionMode
        data          = $safeData
    }

    switch ($Level) {
        'Verbose' { Write-Verbose -Message $safeMessage }
        'Information' { Write-Information -MessageData $safeMessage -InformationAction Continue }
        'Warning' { Write-Warning -Message $safeMessage }
        'Error' { Write-Information -MessageData "[ERROR] $safeMessage" -InformationAction Continue }
        'Audit' { Write-Information -MessageData "[AUDIT] $safeMessage" -InformationAction Continue }
    }

    if ((Get-OcpExecutionMode) -eq 'AzureDevOps') {
        switch ($Level) {
            'Warning' { Write-Host "##vso[task.logissue type=warning]$safeMessage" }
            'Error' { Write-Host "##vso[task.logissue type=error]$safeMessage" }
            'Audit' { Write-Host "##[section]$safeMessage" }
        }
    }

    try {
        $logRoot = Get-OcpLogRoot
        if (-not (Test-Path -LiteralPath $logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force -WhatIf:$false | Out-Null
        }
        $line = ($record | ConvertTo-Json -Compress -Depth 8)
        $line = Protect-OcpSensitiveValue -Text $line
        Add-Content -LiteralPath (Join-Path $logRoot 'openshiftops.jsonl') -Value $line -Encoding UTF8 -WhatIf:$false
    }
    catch {
        Write-Verbose "Unable to persist OpenShiftOps log: $($_.Exception.Message)"
    }
}
