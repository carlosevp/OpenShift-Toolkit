# Operations

## Connecting to a Cluster

```powershell
Get-OcpClusterInfo
Connect-OcpCluster -Cluster Akron-Prod
Get-OcpContext
```

## Read

```powershell
Get-OcpContext
Get-OcpClusterInfo -Cluster Akron-Prod
Get-OcpProject -Cluster Akron-Prod
Get-OcpProjectDetails -Name claims-dev -Cluster Akron-NonProd
Find-OcpUnusedProject -Cluster Akron-NonProd
Test-OcpProjectStandards -Project claims-dev -Cluster Akron-NonProd
Test-OcpProjectStandards -All -Cluster Akron-NonProd
Get-OcpProjectRemovalPlan -Name old-claims-dev -Cluster Pitt-DR
```

`Find-OcpUnusedProject` never deletes. `LastKnownActivity` is `Unknown` unless a reliable timestamp exists.

## Mutate

All mutating commands support `-WhatIf` and `-Confirm`.

```powershell
Set-OcpProjectLabel -Name claims-dev -Key company.com/environment -Value dev -WhatIf
Repair-OcpProjectMetadata -Project claims-dev -Label @{ 'cost-center' = '12345' } -WhatIf
New-OcpProject -Name claims-api-dev -Application claims-api -Environment dev -Owner claims-team -CostCenter 12345
Set-OcpProjectQuota -Name claims-dev -Hard @{ pods = '10' } -WhatIf
```

## Delete

```powershell
Get-OcpProjectRemovalPlan -Name old-claims-dev
Export-OcpProjectSafetySnapshot -Name old-claims-dev
Remove-OcpProject -Name old-claims-dev -WhatIf
Remove-OcpProject -Name old-claims-dev -ChangeReference CHG123456
```

Bulk destructive deletion is not included in the MVP. `Test-OcpBulkSafetyLimit` is available for future bulk remediation (default maximum 10).

## Minimum RBAC

Example Roles are in `docs/rbac/`. Do not apply them automatically. Bind the narrowest Role that matches the service connection privilege.

| Operation | Typical verbs |
| --- | --- |
| Inventory / standards / unused | get, list on namespaces/projects and namespaced resources |
| Label repair | get, patch on namespaces |
| Create project | create on projects/namespaces; create on resourcequotas, limitranges |
| Delete project | get, list, delete on projects; get/list on namespaced resources for export |
