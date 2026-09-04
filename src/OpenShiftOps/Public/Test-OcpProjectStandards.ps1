function Test-OcpProjectStandards {
    <#
    .SYNOPSIS
        Evaluates a project against configured lifecycle label standards.
    .PARAMETER Project
        Project name to evaluate.
    .PARAMETER All
        Evaluate every visible project.
    .PARAMETER Cluster
        Optional cluster alias used to verify the current oc context.
    .PARAMETER Quiet
        Suppresses extra logging for internal callers.
    .EXAMPLE
        Test-OcpProjectStandards -Project claims-dev
    .EXAMPLE
        Test-OcpProjectStandards -All
    .OUTPUTS
        OpenShiftOps.ProjectStandards
    #>
    [CmdletBinding(DefaultParameterSetName = 'One')]
    param(
        [Parameter(ParameterSetName = 'One', Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Name')]
        [string]$Project,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [string]$Cluster,
        [switch]$Quiet
    )

    begin {
        $context = New-OcpOperationContext -Operation 'Test-OcpProjectStandards' -ClusterAlias $Cluster
        $standards = (Get-OcpConfiguration).standards
        $domain = [string]$standards.labelDomain
        $labelDefs = $standards.labels
    }

    process {
        $targets = @()
        if ($All) {
            $targets = @(Get-OcpProject -Cluster $context.ClusterAlias | Select-Object -ExpandProperty Name)
        }
        else {
            $targets = @($Project)
        }

        foreach ($name in $targets) {
            Assert-OcpProjectName -Name $name
            $object = Get-OcpProjectObject -Name $name
            if (-not $object) {
                throw [OcpValidationException]::new("Project '$name' was not found.")
            }

            $missing = New-Object System.Collections.Generic.List[string]
            $invalid = New-Object System.Collections.Generic.List[object]
            $missingAnnotations = New-Object System.Collections.Generic.List[string]
            $warnings = New-Object System.Collections.Generic.List[string]

            foreach ($shortName in $labelDefs.Keys) {
                $definition = $labelDefs[$shortName]
                $key = Get-OcpStandardLabelKey -Name $shortName
                $value = [string](Get-OcpResourceLabel -Resource $object -Key $key)

                if ([string]::IsNullOrWhiteSpace($value)) {
                    if ((Get-OcpProperty -InputObject $definition -Name 'required') -eq $true) {
                        $missing.Add($key)
                    }
                    continue
                }

                if (Test-OcpHasProperty -InputObject $definition -Name 'allowedValues') {
                    $allowed = @($definition.allowedValues | ForEach-Object { [string]$_ })
                    if ($value -notin $allowed) {
                        $mapped = $null
                        if (Test-OcpHasProperty -InputObject $definition -Name 'aliases') {
                            $aliasMap = $definition.aliases
                            if ($aliasMap -and $aliasMap.Contains($value)) {
                                $mapped = [string]$aliasMap[$value]
                            }
                        }
                        $invalid.Add([pscustomobject]@{
                            Key     = $key
                            Value   = $value
                            Allowed = $allowed
                            Alias   = $mapped
                        })
                    }
                }
            }

            if ($standards.annotations) {
                foreach ($annName in $standards.annotations.Keys) {
                    $annDef = $standards.annotations[$annName]
                    if ((Get-OcpProperty -InputObject $annDef -Name 'required') -eq $true) {
                        $annKey = if ($annName -match '/') { $annName } else { "$domain/$annName" }
                        $annotations = Get-OcpProperty -InputObject $object.metadata -Name 'annotations'
                        $annValue = Get-OcpMapValue -Map $annotations -Key $annKey
                        if ([string]::IsNullOrWhiteSpace([string]$annValue)) {
                            $missingAnnotations.Add($annKey)
                        }
                    }
                }
            }

            $compliant = ($missing.Count -eq 0 -and $invalid.Count -eq 0 -and $missingAnnotations.Count -eq 0)
            if (-not $Quiet) {
                Write-OcpLog -Level Verbose -Message "Standards for $name compliant=$compliant" -OperationId $context.OperationId
            }

            [pscustomobject]@{
                PSTypeName          = 'OpenShiftOps.ProjectStandards'
                Project             = $name
                Cluster             = $context.FriendlyName
                ClusterId           = $context.ClusterId
                FriendlyName        = $context.FriendlyName
                Classification      = $context.Classification
                Compliant           = $compliant
                MissingLabels       = $missing.ToArray()
                InvalidLabels       = $invalid.ToArray()
                MissingAnnotations  = $missingAnnotations.ToArray()
                Warnings            = $warnings.ToArray()
                LabelDomain         = $domain
            }
        }
    }
}
