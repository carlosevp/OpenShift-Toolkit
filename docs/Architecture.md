# Architecture

OpenShiftOps is a PowerShell 7 module plus configuration and Azure DevOps YAML. It is intentionally simple so it can be retired or absorbed by a future IDP.

## Trust boundaries

| Path | Authentication | Privilege |
| --- | --- | --- |
| Local existing context | `Connect-OcpCluster -Cluster <friendlyName>` after `oc login` | Whatever the operator already has |
| Local token / API token / bearer token | `Connect-OcpCluster -Token` or `-TokenEnvironmentVariable` (isolated kubeconfig) | Whatever the token's account can do |
| Azure DevOps (preferred) | Mapped Kubernetes service connection for the selected friendly cluster | read / maintenance / destructive |
| Azure DevOps token escape hatch | Secret variable `OCP_TOKEN` + `Connect-OcpCluster -TokenEnvironmentVariable` | Whatever the token's account can do |

The module never stores credentials. `config/clusters.yaml` contains API URLs, friendly names, aliases, and service connection **names**.

## Cluster identity

Each cluster has a canonical ID (`ocp-akron-prod`), a friendly name (`Akron-Prod`), and aliases. Operators usually pass the friendly name. After resolution, every mutation still compares:

```text
configured server URL
==
oc whoami --show-server
```

Friendly names are never treated as proof of which cluster is live.

## Authentication precedence

| Call | Behavior |
| --- | --- |
| `Connect-OcpCluster -Cluster Akron-Prod` | Do not log in again. Validate the current oc context. |
| `Connect-OcpCluster -Cluster Akron-Prod -Token $secure` | `oc login <server> --token` against an isolated kubeconfig, then validate the server. |
| `Connect-OcpCluster -Cluster Pitt-DR -TokenEnvironmentVariable OCP_TOKEN` | Read that variable internally, login, validate. |

`-Token` and `-TokenEnvironmentVariable` cannot be combined. `OCP_TOKEN` is ignored unless that parameter is passed.

## Temporary kubeconfig

Token authentication sets `KUBECONFIG` to a unique file under the process temp directory (`openshiftops-<guid>/kubeconfig`), with restrictive permissions on Unix. The previous `KUBECONFIG` is restored on `Disconnect-OcpCluster`, failed login, or module unload. The operator's existing kubeconfig is never deleted.

Azure DevOps service-connection login continues to use the agent kubeconfig produced by `Kubernetes@1`.

`Get-OcpClusterInfo` is the discovery command. A separate `Get-OcpCluster` alias was not added so the exported command surface stays small.

## Risk model

The module classifies operations itself. Azure DevOps Environments add a second control plane; they are not the only control.

| Risk | Examples |
| --- | --- |
| ReadOnly | Get-OcpContext, Get-OcpProject, Find-OcpUnusedProject, Test-OcpProjectStandards, Get-OcpProjectRemovalPlan |
| Low / Medium | Connect-OcpCluster (token), Set-OcpProjectLabel, Repair-OcpProjectMetadata, New-OcpProject, Set-OcpProjectQuota, Export-OcpProjectSafetySnapshot |
| Destructive | Remove-OcpProject |

## Plan then apply

Dangerous work is split:

1. `Get-OcpProjectRemovalPlan` observes live state and returns a structured plan (`CanProceed`, blockers, PVC evidence).
2. `Export-OcpProjectSafetySnapshot` writes recovery aids and a `backup-manifest.json`.
3. `Remove-OcpProject` rebuilds the plan, verifies the export, then mutates.

A plan object is evidence, not a capability. Stale plans (PVC count change, running pods increased, protection enabled, cluster identity change) abort execution.

## Fail closed

Uncertainty, identity mismatch, failed export, protected namespaces, and PVCs (by default) stop destructive work. There is no `-Force`. The only PVC override is the explicit `-AllowDeleteWithPersistentVolumes` switch, which is disabled by policy until an administrator sets `allowPersistentVolumeOverride: true`.

## Future IDP

Label contracts (`application`, `owner`, `environment`, `cost-center`, `lifecycle`, `managed-by`, `cleanup-protection`, created metadata) live in YAML, not in PowerShell identifiers. A future API can reuse the same files.

## Authoritative cluster catalog

`config/clusters.yaml` is the source of truth for canonical IDs, friendly names, aliases, API URLs, classification, and Azure DevOps connection **names**.

Azure DevOps requires service connection names at YAML compile time, so `pipelines/cluster-map.yml` and `pipelines/templates/authenticate.yml` repeat those names. `tests/unit/PipelineMapping.Tests.ps1` fails if that mapping drifts from the catalog. Do not accept arbitrary service connection names as pipeline parameters.
