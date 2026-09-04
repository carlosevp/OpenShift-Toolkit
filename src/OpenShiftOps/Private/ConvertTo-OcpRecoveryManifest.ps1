function ConvertTo-OcpRecoveryManifest {
    <#
    .SYNOPSIS
        Removes server-generated fields from a Kubernetes object for use as a recovery aid.
    .NOTES
        These manifests are recovery aids, not a guaranteed disaster-recovery restore.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Resource,

        [switch]$ExcludeSecretData
    )

    $json = $Resource | ConvertTo-Json -Depth 20
    $clone = $json | ConvertFrom-Json

    if (Test-OcpHasProperty -InputObject $clone -Name 'metadata') {
        $null = $clone.metadata.PSObject.Properties.Remove('uid')
        $null = $clone.metadata.PSObject.Properties.Remove('resourceVersion')
        $null = $clone.metadata.PSObject.Properties.Remove('generation')
        $null = $clone.metadata.PSObject.Properties.Remove('creationTimestamp')
        $null = $clone.metadata.PSObject.Properties.Remove('managedFields')
        $null = $clone.metadata.PSObject.Properties.Remove('deletionTimestamp')
        $null = $clone.metadata.PSObject.Properties.Remove('deletionGracePeriodSeconds')
        $null = $clone.metadata.PSObject.Properties.Remove('selfLink')

        if (Test-OcpHasProperty -InputObject $clone.metadata -Name 'annotations') {
            foreach ($name in @(
                    'kubectl.kubernetes.io/last-applied-configuration',
                    'deployment.kubernetes.io/revision',
                    'openshift.io/token-secret.name',
                    'openshift.io/sa.secret.name'
                )) {
                if ($clone.metadata.annotations.PSObject.Properties[$name]) {
                    $null = $clone.metadata.annotations.PSObject.Properties.Remove($name)
                }
            }
        }
    }

    $null = $clone.PSObject.Properties.Remove('status')

    if ($clone.kind -eq 'Service' -and (Test-OcpHasProperty -InputObject $clone -Name 'spec')) {
        $null = $clone.spec.PSObject.Properties.Remove('clusterIP')
        $null = $clone.spec.PSObject.Properties.Remove('clusterIPs')
        $null = $clone.spec.PSObject.Properties.Remove('ipFamilies')
        $null = $clone.spec.PSObject.Properties.Remove('ipFamilyPolicy')
    }

        if ($ExcludeSecretData -and $clone.kind -eq 'Secret') {
        $null = $clone.PSObject.Properties.Remove('data')
        $null = $clone.PSObject.Properties.Remove('stringData')
        if (-not (Test-OcpHasProperty -InputObject $clone.metadata -Name 'annotations') -or $null -eq $clone.metadata.annotations) {
            $clone.metadata | Add-Member -NotePropertyName annotations -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $clone.metadata.annotations | Add-Member -NotePropertyName 'openshiftops/secret-data-excluded' -NotePropertyValue 'true' -Force
    }

    return $clone
}

function ConvertTo-OcpYamlDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Resource
    )

    # JSON is a valid YAML subset and avoids a YAML serializer dependency.
    return ($Resource | ConvertTo-Json -Depth 20)
}

function Get-OcpRestorableResourceKinds {
    [CmdletBinding()]
    param()

    return @(
        @{ File = 'resourcequotas.yaml'; Resource = 'resourcequotas' }
        @{ File = 'limitranges.yaml'; Resource = 'limitranges' }
        @{ File = 'serviceaccounts.yaml'; Resource = 'serviceaccounts' }
        @{ File = 'secrets.yaml'; Resource = 'secrets'; Secret = $true }
        @{ File = 'configmaps.yaml'; Resource = 'configmaps' }
        @{ File = 'roles.yaml'; Resource = 'roles.rbac.authorization.k8s.io' }
        @{ File = 'rolebindings.yaml'; Resource = 'rolebindings.rbac.authorization.k8s.io' }
        @{ File = 'networkpolicies.yaml'; Resource = 'networkpolicies.networking.k8s.io' }
        @{ File = 'persistentvolumeclaims.yaml'; Resource = 'persistentvolumeclaims' }
        @{ File = 'services.yaml'; Resource = 'services' }
        @{ File = 'deployments.yaml'; Resource = 'deployments.apps' }
        @{ File = 'statefulsets.yaml'; Resource = 'statefulsets.apps' }
        @{ File = 'daemonsets.yaml'; Resource = 'daemonsets.apps' }
        @{ File = 'cronjobs.yaml'; Resource = 'cronjobs.batch' }
        @{ File = 'routes.yaml'; Resource = 'routes.route.openshift.io' }
        @{ File = 'ingresses.yaml'; Resource = 'ingresses.networking.k8s.io' }
        @{ File = 'horizontalpodautoscalers.yaml'; Resource = 'horizontalpodautoscalers.autoscaling' }
        @{ File = 'buildconfigs.yaml'; Resource = 'buildconfigs.build.openshift.io' }
        @{ File = 'imagestreams.yaml'; Resource = 'imagestreams.image.openshift.io' }
        @{ File = 'deploymentconfigs.yaml'; Resource = 'deploymentconfigs.apps.openshift.io' }
    )
}

function Get-OcpTransientResourceKinds {
    [CmdletBinding()]
    param()

    return @(
        'pods',
        'events',
        'leases.coordination.k8s.io',
        'replicasets.apps',
        'endpoints',
        'endpointslices.discovery.k8s.io',
        'controllerrevisions.apps'
    )
}

function Get-OcpRestoreOrder {
    [CmdletBinding()]
    param()

    return @(
        'Namespace/Project',
        'ResourceQuota',
        'LimitRange',
        'ServiceAccount',
        'Secret (from authoritative secret manager, not this snapshot)',
        'ConfigMap',
        'Role',
        'RoleBinding',
        'NetworkPolicy',
        'PersistentVolumeClaim (manifest only; data is NOT restored)',
        'Service',
        'Deployment / StatefulSet / DaemonSet / DeploymentConfig',
        'CronJob',
        'Route / Ingress',
        'HorizontalPodAutoscaler',
        'BuildConfig / ImageStream'
    )
}
