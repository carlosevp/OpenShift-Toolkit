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

## You must be logged in (Unauthorized)

`oc whoami` is not authenticated. Either:

```powershell
Connect-OcpCluster -Cluster Akron-NonProd -Web
```

or log in first (`oc login --web` / `oc login <server> --web`) and then:

```powershell
Connect-OcpCluster -Cluster Akron-NonProd
```

The second form validates the current context. It does not log in again.

## `openshiftVersion` cannot be found

`oc version -o json` does not always include `openshiftVersion`. Authentication now uses `oc whoami` and treats version fields as optional. Re-import the module (`Import-Module ... -Force`) if you still see this error from an older copy.

## Cluster identity mismatch

The selected cluster's configured URL (normalized) does not match `oc whoami --show-server`. Friendly names are not identity. Log in to the intended cluster with `Connect-OcpCluster` or fix `config/clusters.yaml`. A command for `Akron-NonProd` will not run against `Akron-Prod`.

`server` must be the **API** URL, not the web console. After `oc login --web`:

```powershell
oc whoami --show-server
```

Put that exact value in `config/clusters.yaml`. Example:

```text
Wrong:  https://console-openshift-console.apps.mcluster.mydomain
Right:  https://api.mcluster.mydomain:6443
```

A bare cluster FQDN is also wrong. Re-import the module after editing (`Import-Module ... -Force`).

## Deletion blocked on PVCs

Expected. Exporting YAML does not back up volume data. Use an approved volume backup or, only if policy allows, `-AllowDeleteWithPersistentVolumes`.

## Deletion blocked on protected project

Expected. `openshift-*`, `kube-*`, exact system names, and `cleanup-protection=true` cannot be deleted with this toolkit.

## Stale plan after Azure DevOps approval

The live cluster changed (PVCs, running pods, protection, or identity). Generate a new plan and repeat approval.

## Secret values in artifacts

The publish step should fail the pipeline. Default export strips Secret data. Do not set `secretExport.enabled` to true; the module refuses that configuration.

## Web login failed

`-Web` runs `oc login <configured-server> --web` and waits for the browser. It is refused in Azure DevOps. If the browser does not open, copy the URL `oc` prints. Confirm `config/clusters.yaml` has the real API URL for that friendly name.

## Token login failed

The API / bearer token is invalid, expired, or the environment variable was empty. The token value is not printed. For local use pass a SecureString. For pipelines, confirm `OCP_TOKEN` is a secret variable and `AuthenticationMethod` is `Token`.
