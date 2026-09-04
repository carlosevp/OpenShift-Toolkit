# Changelog

## 0.2.1 - 2026-09-04

- `Connect-OcpCluster -Web` for `oc login <server> --web` (interactive browser / OAuth)
- Authentication no longer fails when `oc version` omits `openshiftVersion`

## 0.2.0 - 2026-09-04

- Friendly cluster names, aliases, and canonical IDs with case-insensitive resolution
- `Connect-OcpCluster` for existing context and Token / API token / bearer token authentication
- Isolated temporary kubeconfig for token sessions
- Azure DevOps friendly-name selection with compile-time service connection mapping tests

## 0.1.0 - 2026-09-04

Initial MVP.

- Read-only inventory, standards validation, and unused-project scoring
- Safe label and metadata mutations with ShouldProcess and recovery records
- Standardized project creation from configurable baseline templates
- Plan/apply project deletion with protected-project rules, PVC blocking, safety export, export verification, revalidation, and audit
- Azure DevOps parameterized pipeline with compile-time service connection mapping and Environment-based approval stages
- Pester unit tests for safety-critical behavior
