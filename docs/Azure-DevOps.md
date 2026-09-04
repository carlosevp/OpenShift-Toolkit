# Azure DevOps

This YAML does **not** create manual approvals. Administrators must configure Azure DevOps Environments with checks. Editing pipeline YAML must not be enough to bypass those checks.

Operators select a **friendly cluster name**. They never type a service connection name.

```text
Akron-Prod
    ↓
ocp-akron-prod   (canonical ID from config/clusters.yaml)
    ↓
OCP-AKRON-PROD   (or OCP-AKRON-PROD-DESTRUCTIVE)
```

## Authoritative catalog vs compile-time YAML

`config/clusters.yaml` is the source of truth for cluster identity and connection **names**.

Azure DevOps requires service connection names at compile time, so `pipelines/templates/authenticate.yml` and `pipelines/cluster-map.yml` repeat those names. If you add a cluster:

1. Add it to `config/clusters.yaml`
2. Copy the same friendly name and connection names into `pipelines/cluster-map.yml`
3. Add explicit conditions in `pipelines/templates/authenticate.yml`
4. Add the friendly name to the Cluster parameter in `pipelines/openshift-ops.yml`
5. Run `tests/unit/PipelineMapping.Tests.ps1`

Do not attempt to pass arbitrary service connection names as pipeline parameters.

## Environments to create

Create these Environments in the Azure DevOps project (Pipelines > Environments):

| Environment | Used for |
| --- | --- |
| `openshift-nonprod-maintenance` | Create/repair on Akron-NonProd |
| `openshift-prod-maintenance` | Create/repair on Akron-Prod, Pitt-Prod, Pitt-DR |
| `openshift-destructive` | Project deletion on Akron-NonProd |
| `openshift-prod-destructive` | Project deletion on production clusters |

On each Environment add:

1. Approvals and checks > Approvals
2. Approvers (a group, not a single shared account)
3. Optional: required template check so only this repository's pipeline can use the Environment
4. Optional: branch control (protected default branch only)

## Service connections

Reuse existing Kubernetes/OpenShift service connections. Names are configured per cluster in `config/clusters.yaml`.

Prefer separate connections:

| Privilege | Connection purpose |
| --- | --- |
| Read / maintenance | list/get, labels, create project, quotas |
| Destructive | delete projects |

Example names in the sample catalog: `OCP-AKRON-PROD` and `OCP-AKRON-PROD-DESTRUCTIVE`.

## Authentication methods

The pipeline parameter `AuthenticationMethod` defaults to `ServiceConnection` (preferred).

`Token` is an escape hatch: set a secret variable named `OCP_TOKEN` (never in YAML) and `Connect-OcpCluster -TokenEnvironmentVariable OCP_TOKEN` runs inside an isolated kubeconfig. Do not echo the variable.

## Pipeline

1. Create a pipeline from `pipelines/openshift-ops.yml`.
2. Restrict who can queue it. Treat `DeleteProject` as a privileged operation.
3. Grant the pipeline permission to use the Environments and service connections (Pipeline permissions on each).
4. Ensure agents have PowerShell 7 (`pwsh`) and `oc`.
5. The Kubernetes@1 `login` task requires the Kubernetes extension and a working kubeconfig afterward.

## Destructive flow

`DeleteProject` runs two stages:

1. **Plan** — authenticate (read), generate plan, safety export, publish non-sensitive artifacts
2. **Destroy** — Environment approval, re-authenticate (destructive), revalidate **including live API server identity**, delete, verify, audit

If the plan is stale after approval, the apply stage fails closed and a new run is required.

## Artifacts

Published under `openshiftops-results`:

- `plan.json` / `plan.md`
- `inventory.json`
- sanitized resource manifests (no secret values)
- `backup-manifest.json`
- `audit.json` / `result.json` / `summary.md`

A publish step refuses files that look like they contain bearer tokens or secret data. Audit records include `clusterId`, `clusterFriendlyName`, `authenticatedIdentity`, and `authenticationMethod` — never the token.
