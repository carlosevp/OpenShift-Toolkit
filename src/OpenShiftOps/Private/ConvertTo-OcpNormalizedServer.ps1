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

function Assert-OcpApiServerUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClusterId,

        [Parameter(Mandatory = $true)]
        [string]$Server
    )

    $hostName = ([Uri]$Server).Host
    if ($hostName -match '(?i)^console-openshift-console(\.|$)' -or $hostName -match '(?i)\.apps\.') {
        throw [OcpConfigurationException]::new(
            @"
Cluster '$ClusterId' server '$Server' looks like an OpenShift web console or apps route, not the API server.

oc and this module authenticate to the Kubernetes API, usually:

  https://api.<cluster>.<domain>:6443

Get the exact value after login:

  oc whoami --show-server

Put that URL in config/clusters.yaml. Do not use console-openshift-console.apps...
"@.Trim()
        )
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
