# Getting started

## Local setup

1. Install PowerShell 7+ and the OpenShift CLI.
2. Edit **`config/clusters.yaml`** with real API URLs, friendly names, and aliases. This is the catalog `Connect-OcpCluster` and `Get-OcpClusterInfo` read. Do not add credentials.
3. Set `standards.labelDomain` in `config/project-standards.yaml` (replace `company.com`).
4. Align protected-project label keys with that domain.
5. Import the module (`Import-Module ./src/OpenShiftOps/OpenShiftOps.psd1`). After later catalog edits, use `-Force` so the new file is loaded.

## Connecting to a Cluster

List configured clusters (no live login required):

```powershell
Import-Module ./src/OpenShiftOps/OpenShiftOps.psd1
Get-OcpClusterInfo
```

### Existing oc context

```bash
oc login --server https://api.ocp-akron-prod.example.com:6443
```

```powershell
Connect-OcpCluster -Cluster Akron-Prod
Get-OcpContext
Get-OcpProject -Cluster Akron-Prod
```

`Connect-OcpCluster -Cluster Akron-Prod` does **not** log in again. It validates that the current `oc` server matches Akron-Prod.

### API / bearer token

```powershell
$token = Read-Host 'OpenShift API token' -AsSecureString
Connect-OcpCluster -Cluster Akron-Prod -Token $token
```

Token authentication uses an isolated temporary kubeconfig. It does not replace your default kubeconfig. `Disconnect-OcpCluster` restores the previous `KUBECONFIG` and deletes only the temporary file.

### Environment variable token

```powershell
$env:OCP_CLUSTER = 'Akron-Prod'
Connect-OcpCluster -Cluster $env:OCP_CLUSTER -TokenEnvironmentVariable OCP_TOKEN
```

`OCP_TOKEN` is never consumed automatically. You must pass `-TokenEnvironmentVariable`.

Friendly names, aliases, and canonical IDs are case-insensitive. Unknown names fail. There is no fuzzy matching (`akron-prd` does not become `Akron-Prod`).

## Preview a mutation

```powershell
Repair-OcpProjectMetadata -Project claims-dev -Cluster Akron-NonProd -WhatIf
Set-OcpProjectLabel -Name claims-dev -Key company.com/environment -Value dev -Cluster Akron-NonProd -WhatIf
```

Optional environment variables:

| Variable | Purpose |
| --- | --- |
| `OCP_CLUSTER` | Default cluster name for `Connect-OcpCluster` |
| `OCP_TOKEN` | API / bearer token **only** when `-TokenEnvironmentVariable OCP_TOKEN` is used |
| `OPENSHIFTOPS_CONFIG_ROOT` | Alternate config directory |
| `OPENSHIFTOPS_ARTIFACT_ROOT` | Safety export / audit output |
| `OPENSHIFTOPS_LOG_ROOT` | JSONL logs |
| `OPENSHIFTOPS_OC_PATH` | Explicit `oc` binary |

## Azure DevOps

See [Azure-DevOps.md](Azure-DevOps.md). The pipeline YAML cannot create Environment approvals by itself.
