# Troubleshooting

## Module fails on import

Configuration is validated immediately and fails closed. Typical causes:

- `config/` not found (set `OPENSHIFTOPS_CONFIG_ROOT`)
- Duplicate friendly names or aliases in `config/clusters.yaml`
- Missing `friendlyName` or `azureDevOps.serviceConnection`
- `secretExport.enabled` is not `false`
- Required deletion safety flags were turned off

## `oc` not found

Install the OpenShift CLI or set `OPENSHIFTOPS_OC_PATH`. Azure DevOps agents must have `oc` after the Kubernetes login task.

## Cluster identity mismatch

The selected cluster's configured URL (normalized) does not match `oc whoami --show-server`. Friendly names are not identity. Log in to the intended cluster with `Connect-OcpCluster` or fix `config/clusters.yaml`. A command for `Akron-NonProd` will not run against `Akron-Prod`.

## Deletion blocked on PVCs

Expected. Exporting YAML does not back up volume data. Use an approved volume backup or, only if policy allows, `-AllowDeleteWithPersistentVolumes`.

## Deletion blocked on protected project

Expected. `openshift-*`, `kube-*`, exact system names, and `cleanup-protection=true` cannot be deleted with this toolkit.

## Stale plan after Azure DevOps approval

The live cluster changed (PVCs, running pods, protection, or identity). Generate a new plan and repeat approval.

## Secret values in artifacts

The publish step should fail the pipeline. Default export strips Secret data. Do not set `secretExport.enabled` to true; the module refuses that configuration.

## Token login failed

The API / bearer token is invalid, expired, or the environment variable was empty. The token value is not printed. For local use pass a SecureString. For pipelines, confirm `OCP_TOKEN` is a secret variable and `AuthenticationMethod` is `Token`.
