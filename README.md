# OpenShiftOps

Internal PowerShell toolkit for common OpenShift administrative operations. It is a lightweight operational band-aid while a fuller Internal Developer Platform is built.

There is no custom UI and no API service. Engineers run the same module locally (after `oc login`) or from Azure DevOps (after an existing OpenShift/Kubernetes service connection). All business logic lives in the module. Pipelines handle authentication, parameters, approvals, artifacts, and audit context.

```text
Engineer
   |
   +-- Local PowerShell
   |       |
   |       +-- existing oc login
   |
   +-- Azure DevOps Pipeline
           |
           +-- existing OpenShift/Kubernetes service connections
                    |
                    v
             OpenShiftOps
             PowerShell Module
                    |
                    v
                  oc CLI
                    |
                    v
            OpenShift Clusters
```

## Requirements

- PowerShell 7+
- OpenShift CLI (`oc`) on PATH
- An authenticated `oc` context, or an API / bearer token for `Connect-OcpCluster`

## How to start

There is no setup wizard after you import the module. Edit YAML, then import.

### 1. Configure clusters

Edit **[config/clusters.yaml](config/clusters.yaml)**. That file is the catalog of friendly names, aliases, API URLs, and Azure DevOps connection names.

Replace the example `Akron-*` / `Pitt-*` entries with your real clusters. Do not put tokens, passwords, or kubeconfig data in this file.

```yaml
clusters:
  ocp-akron-prod:                    # canonical ID (internal, lowercase)
    friendlyName: Akron-Prod         # what operators type
    aliases:
      - akron-prod
      - akr-prod
    server: https://api.ocp-akron-prod.example.com:6443   # API URL from: oc whoami --show-server
    # not the web console (console-openshift-console.apps...)
    classification: production       # nonprod or production
    location: Akron
    purpose: primary
    azureDevOps:
      serviceConnection: OCP-AKRON-PROD
      destructiveServiceConnection: OCP-AKRON-PROD-DESTRUCTIVE
```

Also set `standards.labelDomain` in [config/project-standards.yaml](config/project-standards.yaml) (replace `company.com`).

If you change friendly names used by pipelines, update `pipelines/cluster-map.yml`, `pipelines/templates/authenticate.yml`, and the Cluster values in `pipelines/openshift-ops.yml` to match. `pwsh -File ./tests/Invoke-OcpTests.ps1` will fail if those mappings drift.

### 2. Import the module

```powershell
Import-Module ./src/OpenShiftOps/OpenShiftOps.psd1
```

The module reads `config/` at import time and fails closed if the catalog is invalid (duplicate aliases, missing `friendlyName`, non-https server, and so on).

After you edit `config/clusters.yaml`, re-import so the new catalog is loaded:

```powershell
Import-Module ./src/OpenShiftOps/OpenShiftOps.psd1 -Force
```

To point at a different config directory: `$env:OPENSHIFTOPS_CONFIG_ROOT = '/path/to/config'`.

### 3. Confirm and connect

```powershell
Get-OcpClusterInfo

# Browser / OAuth (oc login --web)
Connect-OcpCluster -Cluster Akron-Prod -Web

# Existing oc login — validates the current server against the catalog
Connect-OcpCluster -Cluster Akron-Prod

# Or token / API token / bearer token
$token = Read-Host 'OpenShift API token' -AsSecureString
Connect-OcpCluster -Cluster Akron-Prod -Token $token
```

Then:

```powershell
Get-OcpContext
Get-OcpProject -Cluster Akron-Prod
Find-OcpUnusedProject
Test-OcpProjectStandards -Project claims-dev
Repair-OcpProjectMetadata -Project claims-dev -WhatIf
Get-OcpProjectRemovalPlan -Name old-claims-dev
Export-OcpProjectSafetySnapshot -Name old-claims-dev
Remove-OcpProject -Name old-claims-dev -WhatIf
```

More detail: [Getting started](docs/Getting-Started.md).

## What happens before a real project deletion

1. The current `oc` server is compared to the selected cluster's configured API URL. Friendly names are not proof of identity. Mismatch fails closed.
2. The project is checked against protected/system rules. There is no override for those namespaces.
3. A live removal plan is generated (`Get-OcpProjectRemovalPlan`).
4. PersistentVolumeClaims block deletion by default.
5. A safety export is created and verified. If the export fails, deletion does not run.
6. `-WhatIf` / `-Confirm` are honored. Pipelines additionally require a protected Azure DevOps Environment.
7. Immediately before `oc delete project`, identity, protection, PVCs, and material plan fields are revalidated.
8. An audit record is written. Secret values are never written to logs or artifacts.

## What the Safety Snapshot DOES NOT Protect

Manifest exports do not back up persistent volume data.

Manifest exports do not necessarily contain secret values.

Manifest exports are recovery aids and not a replacement for enterprise backup/disaster recovery.

A YAML dump of a namespace is a **Safety Export**, not a **Persistent Data Backup**.

## Connecting to a Cluster

Friendly names such as `Akron-Prod` are lookup aliases for configured canonical clusters. They never replace API-server identity verification.

```powershell
Get-OcpClusterInfo

Connect-OcpCluster -Cluster Akron-Prod -Web

Connect-OcpCluster -Cluster Akron-Prod

$token = Read-Host 'OpenShift API token' -AsSecureString
Connect-OcpCluster -Cluster Akron-Prod -Token $token

Connect-OcpCluster -Cluster Pitt-DR -TokenEnvironmentVariable OCP_TOKEN
```

## Intent-based commands

This module does not expose a generic `Invoke-OcCommand`. Operators use intent-oriented functions such as `Get-OcpProject`, `Test-OcpProjectStandards`, `Repair-OcpProjectMetadata`, and `Remove-OcpProject`.

## Documentation

- [Architecture](docs/Architecture.md)
- [Getting started](docs/Getting-Started.md)
- [Security](docs/Security.md)
- [Azure DevOps](docs/Azure-DevOps.md)
- [Backup and recovery](docs/Backup-And-Recovery.md)
- [Operations](docs/Operations.md)
- [Troubleshooting](docs/Troubleshooting.md)

## Tests

```powershell
pwsh -File ./tests/Invoke-OcpTests.ps1
```

Read-only live tests (requires `oc login`):

```powershell
$env:OPENSHIFTOPS_INTEGRATION = '1'
pwsh -File ./tests/Invoke-OcpTests.ps1 -Integration
```

Normal automated tests never delete a real namespace.
