# Azure Admin Lab — Entra ID Identity Governance (LAB)

An identity-administration lab focused on the **governance** side of
Microsoft Entra ID (Azure AD): Conditional Access policy design, Privileged
Identity Management procedures, Key Vault secret rotation, and MFA coverage
reporting. The companion `azure-hybrid-network` project covers the
networking side; this one covers who gets in, with what, and who approved it.

> **LAB — nothing here touches a real directory.** Every policy is a
> `disabled` template with `REPLACE_ME` placeholders, every procedure is a
> runbook on paper, and the reporting script reads a fictional CSV — it
> never calls Microsoft Graph or any network endpoint. Deployment needs
> your own Azure/Entra tenant.

**What this demonstrates:** Conditional Access policy design (MFA for
admins, legacy-auth blocking, device trust) authored as reviewable JSON in
Graph schema; PIM concepts (eligible vs. active assignments, approval
workflows, access-review cadence); a Key Vault rotation procedure with an
audit trail; and a read-only PowerShell reporting tool that computes MFA
coverage from exported data — with honest validation, all run in this
sandbox.

```
   identity governance (this lab)          networking (companion lab)
   ┌──────────────────────────────┐       ┌───────────────────────────┐
   │  docs/identity-governance.md │       │   azure-hybrid-network    │
   │  CA policies A/B/C (TEMPLATE │       │   VNets, subnets, NSGs,   │
   │  JSON, Graph schema)         │       │   hybrid connectivity     │
   └──────────────┬───────────────┘       └───────────────────────────┘
                  │ evaluated at every sign-in
   ┌──────────────▼───────────────┐
   │  docs/pim-keyvault.md        │  eligible vs active, approvals,
   │  PIM runbook + KV rotation  │  reviews, rotation procedure
   └──────────────┬───────────────┘
                  │
   ┌──────────────▼───────────────┐
   │  scripts/Get-MfaCoverageReport.ps1 ──▶ users.csv.example (fictional)
   │  read-only MFA audit from CSV export — no live tenant calls
   └──────────────────────────────┘
```

## Repo layout

| Path | Purpose |
|---|---|
| `docs/identity-governance.md` | CA framework explainer + 3 template JSON policies (MFA for admins, block legacy auth, managed-device requirement) |
| `docs/pim-keyvault.md` | PIM runbook: eligible vs. active, approval workflow, access-review cadence; Key Vault secret-rotation procedure |
| `docs/architecture.md` | Design decisions: why CA-first, defense-in-depth identity, least privilege, CSV-first reporting |
| `docs/interview-answers.md` | "How did you design this?" — talking points for interviews |
| `scripts/Get-MfaCoverageReport.ps1` | Read-only MFA coverage report from an exported CSV (never touches a live tenant) |
| `scripts/users.csv.example` | Fictional `contoso.example` user data for the report script |
| `scripts/Export-KeyVaultInventory.ps1` | Guarded template skeleton for a Key Vault secret inventory (exits by design until configured) |
| `.gitignore` | Real `*.csv` exports are never committed; only `*.csv.example` ships |

## Quick start

```powershell
# Run the MFA coverage report against the fictional example data
# (PowerShell 7+; no Azure modules, no sign-in, no network calls)
./scripts/Get-MfaCoverageReport.ps1

# Against your own exported CSV, with a JSON summary on the side
./scripts/Get-MfaCoverageReport.ps1 -InputCsv ./users-export.csv -OutputPath ./mfa-report.json
# ^ do NOT commit users-export.csv — see .gitignore

# Review the Conditional Access templates (disabled by design)
# docs/identity-governance.md — replace every REPLACE_ME before use,
# deploy report-only first, in your own tenant only.

# The Key Vault script is a template: it prints its setup instructions and exits.
./scripts/Export-KeyVaultInventory.ps1 -VaultName 'kv-your-vault-01'
```

## Security notes

- **No credentials, tenant IDs, or secrets anywhere in this repo** — the
  secret scan in Validation confirms it. The only GUIDs present are
  Microsoft's public, well-known Entra role template IDs.
- **Nothing phones home.** The reporting script imports a CSV and writes to
  stdout; the inventory script stops at its guard block. There is no
  `Connect-AzAccount`, no Graph call, no network endpoint in any executable
  path.
- **Templates fail closed.** Every CA policy ships `state: disabled` with
  `REPLACE_ME` break-glass exclusions, so a copy-paste can never go live or
  lock anyone out by accident.
- **Real exports stay out of git.** `.gitignore` blocks `*.csv` (except the
  fictional `*.csv.example`) because real user exports are PII.

## Validation (actually run in this sandbox)

PowerShell 7 parser — 0 syntax errors on both scripts:

```
PARSER Get-MfaCoverageReport.ps1: 0 error(s)
PARSER Export-KeyVaultInventory.ps1: 0 error(s)
```

PSScriptAnalyzer 1.25.0 (default rules) — 0 findings on both scripts. Two
initial findings were fixed at source, no suppressions: missing UTF-8 BOM on
both files, and two unused parameters in the inventory template (now
referenced in the guard block's verbose message).

```
ANALYZER Get-MfaCoverageReport.ps1: 0 finding(s)
ANALYZER Export-KeyVaultInventory.ps1: 0 finding(s)
```

All 3 Conditional Access JSON templates parse cleanly (`python3 -m json.tool`
equivalent check over the embedded blocks):

```
[1] parse OK — displayName="TEMPLATE — Require MFA for all administrators" state=disabled
[2] parse OK — displayName="TEMPLATE — Block legacy authentication" state=disabled
[3] parse OK — displayName="TEMPLATE — Require managed device for corporate apps" state=disabled
```

Real run of the report script against the fictional `users.csv.example`
(12 users — all data fictional, nothing redacted because nothing is real):

```
=== MFA Coverage Report (LAB — CSV data, no live tenant) ===
Source file : users.csv.example
Generated   : 2026-10-20 20:56:04Z UTC

Total users        : 12
With MFA registered: 8
Without MFA        : 4
Coverage           : 66.7%

--- Auth method breakdown (registered users) ---
phone                      5 user(s)
microsoftAuthenticator     4 user(s)
email                      3 user(s)
fido2                      1 user(s)
temporaryAccessPass        1 user(s)

--- Users WITHOUT MFA ---

UPN                          Name         Department Admin LastSignInDaysAgo
---                          ----         ---------- ----- -----------------
amelia.davis@contoso.example Amelia Davis HR         False 45
ethan.garcia@contoso.example Ethan Garcia Operations True  30
emma.silva@contoso.example   Emma Silva   Sales      False 12
sophia.reyes@contoso.example Sophia Reyes HR         False 5

!!! CRITICAL: privileged admins WITHOUT MFA !!!
  - ethan.garcia@contoso.example (Ethan Garcia)

--- Stale accounts (>= 30 days since sign-in) without MFA ---
  - ethan.garcia@contoso.example (30d inactive)
  - amelia.davis@contoso.example (45d inactive)
```

The template guard works as designed — the inventory script refuses to run
until configured:

```
$ ./scripts/Export-KeyVaultInventory.ps1 -VaultName 'kv-lab-test-01'
WARNING: TEMPLATE ONLY: Export-KeyVaultInventory.ps1 does not run against a real vault.
...
Nothing was queried, listed, or exported. No vault was touched.
```

Secret scan — `grep` over the whole project for GUIDs, key/secret patterns,
and long base64-ish tokens: **clean**. The only GUIDs present are the five
documented public Entra role template IDs (Global Admin, Privileged Auth
Admin, Auth Admin, User Admin, CA Admin). No tenant IDs, no secrets, no keys.

**Honest statement:** nothing in this lab was deployed to a real tenant, and
nothing here can deploy itself. The policies are templates, the procedures
are runbooks, and the scripts process local CSV data only. Turning any of
this into production requires the user's own Azure/Entra tenant, the
report-only rollout order documented in `docs/identity-governance.md`, and a
human approving every step.
