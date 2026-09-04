# Backup and recovery

## Safety Export vs Persistent Data Backup

| Kind | What it is | What it is not |
| --- | --- | --- |
| Safety Export | Sanitized YAML/JSON of configuration objects plus inventory | A backup of PVC bytes or secret values |
| Persistent Data Backup | Volume snapshot / Velero / enterprise storage backup | Something ManifestExport can claim |

`Export-OcpProjectSafetySnapshot` always uses the built-in **ManifestExport** provider in this MVP.

## Snapshot layout

```text
artifacts/
  2026-09-04T150501Z/
    <operation-id>/
      metadata.json
      summary.md
      project.yaml
      inventory.json
      backup-manifest.json
      resources/
        deployments.yaml
        ...
      recovery/
        recovery-summary.md
        restore-order.json
```

Inventory may include transient objects (pods, events, replica sets) for audit. Restorable files are a curated set with server-generated fields removed.

## What the Safety Snapshot DOES NOT Protect

- Persistent volume data / PVC contents
- Kubernetes/OpenShift Secret values (excluded by policy)
- Transient runtime objects
- A guaranteed full restore

These manifests are **recovery aids**.

## PVC rule

If PVCs exist, `CanProceed` is false and `Remove-OcpProject` fails closed. A YAML export does not protect application data.

## Future providers

`Test-OcpBackupProvider`, `Start-OcpBackup`, `Wait-OcpBackup`, `Test-OcpBackupCompleted`, and `Get-OcpBackupDetails` exist so Velero or CSI snapshot integration can be added without rewriting `Remove-OcpProject`. Velero is not a dependency. Until a provider can set `PersistentDataBackupVerified = true`, PVC-containing projects stay blocked unless the explicit policy override is used.
