# Security

## Rules enforced by the toolkit

- No `Invoke-Expression`
- No generic user-supplied shell/oc command wrapper
- No credentials in configuration
- Tokens, passwords, kubeconfig material, and Secret `data` are redacted from logs
- Secret values are never written to normal Azure DevOps artifacts
- Project names, cluster aliases, and label keys/values are validated
- Cluster identity is checked before mutations (`oc whoami --show-server` vs the **configured server URL** of the resolved cluster). Friendly names are not identity.
- API / bearer tokens are never logged, audited, returned, or written to artifacts
- Duplicate cluster IDs, friendly names, or aliases fail closed at configuration load
- Destructive actions fail closed on uncertainty
- Protected/system projects cannot be deleted; no toolkit override exists for them

## Secrets policy

Default and only supported setting:

```yaml
safety:
  secretExport:
    enabled: false
```

Safety exports include Secret **names**, **types**, and metadata. They do not include `data` or `stringData`.

Recover secrets from the authoritative source used in that environment (External Secrets, Vault, Azure Key Vault, GitOps, Sealed Secrets, or another enterprise mechanism). This toolkit does not assume any particular manager exists.

## Overrides

Do not use `-Force`.

`-AllowDeleteWithPersistentVolumes` is intentionally verbose. It is ignored unless `safety.projectDeletion.allowPersistentVolumeOverride` is `true`, always produces a high-severity audit event, still requires confirmation locally, and still requires the destructive Azure DevOps Environment path in pipelines.

## Token / API token / bearer token handling

`Connect-OcpCluster` supports Token authentication. Prefer a `SecureString` locally and an Azure DevOps **secret** variable for automation. Tokens are read internally, passed to `oc` as an argument array, and redacted as `--token=***REDACTED***` in logs. Service account identities such as `system:serviceaccount:<namespace>:<sa>` are valid; permissions are still checked with `oc auth can-i`.

Do not put tokens in `config/`, pipeline YAML, or example scripts.

## Remaining risks

See the Security Review section in the implementation hand-off. Operators with an already-authenticated high-privilege `oc` context can still do damage locally; the module reduces accidents, it does not replace IAM.
