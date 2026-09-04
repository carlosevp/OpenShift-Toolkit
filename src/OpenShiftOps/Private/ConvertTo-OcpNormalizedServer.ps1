function ConvertTo-OcpNormalizedServer {
    <#
    .SYNOPSIS
        Normalizes an OpenShift API server URL for identity comparison.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Server
    )

    process {
        $value = $Server.Trim().TrimEnd('/')
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw [OcpValidationException]::new('Server URL cannot be empty.')
        }

        if ($value -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
            $value = "https://$value"
        }

        try {
            $uri = [Uri]$value
        }
        catch {
            throw [OcpValidationException]::new("Server URL '$Server' is not a valid URI.")
        }

        if (-not $uri.IsAbsoluteUri) {
            throw [OcpValidationException]::new("Server URL '$Server' must be absolute.")
        }

        $scheme = $uri.Scheme.ToLowerInvariant()
        $hostName = $uri.IdnHost.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($hostName)) {
            $hostName = $uri.Host.ToLowerInvariant()
        }

        $port = $uri.Port
        if ($port -lt 0) {
            $port = if ($scheme -eq 'https') { 443 } else { 80 }
        }

        return "${scheme}://${hostName}:${port}"
    }
}

function Test-OcpServerUrlMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Actual
    )

    return (ConvertTo-OcpNormalizedServer -Server $Expected) -eq (ConvertTo-OcpNormalizedServer -Server $Actual)
}
