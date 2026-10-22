# Identity Governance — Conditional Access Policy Design

**Scope:** template policy design for a Microsoft Entra ID (Azure AD) tenant.
**Status:** Offline design — nothing here is deployed. The JSON below is a *design
template* in Microsoft Graph `conditionalAccessPolicy` schema, ready to be
reviewed and applied in **your own tenant's test environment** only.
State is `disabled` in every template so a copy-paste can never go live by
accident. Replace every `REPLACE_ME` placeholder before use.

---

## 1. How Conditional Access works

Conditional Access is the policy engine that sits in front of every Entra ID
authentication. Each sign-in is evaluated against a set of policies in a
fixed evaluation order:

1. **Signals** — who is signing in, what device, from where, which client app,
   what risk level the identity protection engines report.
2. **Conditions** — each policy declares the signals it applies to: which
   users (or directory roles), which target applications, which platforms,
   locations, and client app types.
3. **Grant controls** — what must happen for access to be granted: require MFA,
   require a compliant device, require a specific auth strength, or **block**.
4. **Session controls** — what happens *after* access is granted (app-enforced
   restrictions, sign-in frequency, Conditional Access App Control).

Key facts that drive the design below:

- Policies are evaluated with **OR logic between policies** (a sign-in only
  needs to satisfy all policies that apply to it) and **AND logic inside a
  policy** (all conditions must match, all grant controls must be satisfied).
- The **"All" wildcard** is powerful and dangerous: `includeUsers: ["All"]`
  with `includeRoles` covering admin role templates is how you catch every
  privileged account, including ones created tomorrow.
- **Break-glass accounts are always excluded.** Every block/grant policy that
  could lock you out must exclude at least two emergency-access accounts with
  FIDO2 credentials stored in a safe. This is non-negotiable — a CA misconfig
  that locks out the only Global Admins is a tenant-recovery incident.
- **Report-only mode first.** Every policy goes through `state: report-only`
  for at least one business week (two is better). The sign-in log's
  "Report-only" view shows exactly which real sign-ins *would have* been
  affected. Only then does the policy go `enabled`.
- **Legacy authentication has no MFA signal to evaluate.** Clients using
  basic auth (old Office clients, IMAP/POP/SMTP with basic auth, old EAS)
  cannot do MFA at all, so they must be *blocked*, not granted-with-MFA.

## 2. Design principles used in these templates

1. **CA-first, not password-first.** Password policy is the floor; Conditional
   Access is the wall. Assume passwords are compromised (phishing works) and
   design every policy as if the attacker already knows the credential.
2. **Least privilege on the admin plane.** Admins get MFA *and* nothing else
   extra — the same users see policy (b) and (c) too; admin accounts simply
   have the strictest combination.
3. **Explicit exclusions, documented.** Excluded users/groups are listed with
   a `REPLACE_ME` placeholder and a reason comment so reviewers can audit them.
4. **Rollout = report-only → pilot group → all.** The templates are disabled;
   the rollout order (report-only first) is part of the procedure, not optional.

---

## Template A — Require MFA for all administrators

**Intent:** any sign-in by a holder of a privileged directory role must
satisfy MFA, regardless of device, location, or client app. This is the
highest-priority policy in any Entra tenant: admin accounts are the keys to
the whole directory.

**Included roles** are referenced by Entra's immutable role template IDs, so
the policy survives role renames:

- Global Administrator — `62e90394-69f5-4237-9190-012177145e10`
- Privileged Authentication Administrator — `7be44c8a-adaf-4a4a-84bd-20c72776aec3`
- Authentication Administrator — `c4e39bd9-1100-46d3-8c65-fb160da0071f`
- User Administrator — `fe930be7-5e62-47db-91af-98c3a49a38b11`
- Conditional Access Administrator — `b1be1c3e-b65d-4f19-8427-f6fa0d97feb9`

> **TEMPLATE** — `state: disabled`, placeholders must be replaced.

```json
{
  "displayName": "TEMPLATE — Require MFA for all administrators",
  "state": "disabled",
  "description": "TEMPLATE: require MFA on every sign-in by privileged admin role holders. Replace REPLACE_ME exclusions, test in report-only mode, then enable.",
  "conditions": {
    "users": {
      "includeRoles": [
        "62e90394-69f5-4237-9190-012177145e10",
        "7be44c8a-adaf-4a4a-84bd-20c72776aec3",
        "c4e39bd9-1100-46d3-8c65-fb160da0071f",
        "fe930be7-5e62-47db-91af-98c3a49a38b11",
        "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9"
      ],
      "excludeUsers": [
        "REPLACE_ME-break-glass-account-1-object-id",
        "REPLACE_ME-break-glass-account-2-object-id"
      ],
      "includeUsers": [],
      "excludeGroups": [],
      "excludeRoles": []
    },
    "applications": {
      "includeApplications": ["All"],
      "excludeApplications": []
    },
    "clientAppTypes": ["all"],
    "platforms": null,
    "locations": null,
    "devices": null,
    "userRiskLevels": [],
    "signInRiskLevels": []
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["mfa"]
  },
  "sessionControls": null
}
```

**Why `clientAppTypes: ["all"]` and not "browser/mobile only":** admins also
sign in via PowerShell/Graph clients. Excluding modern auth clients would
leave `Connect-AzAccount` sessions unprotected.

**Rollout note:** break-glass accounts are excluded because they use FIDO2
hardware keys (phishing-resistant MFA) and are *monitored*, not MFA'd per
policy — see `docs/pim-keyvault.md` for the break-glass procedure.

---

## Template B — Block legacy authentication

**Intent:** legacy (basic) authentication protocols cannot do MFA, so they
are the hole in every MFA policy. Block them tenant-wide. In Graph, legacy
auth is selected with `clientAppTypes: ["exchangeActiveSync", "other"]` —
`other` covers IMAP, POP3, SMTP with basic auth and old Office clients.

> **TEMPLATE** — `state: disabled`, placeholders must be replaced.

```json
{
  "displayName": "TEMPLATE — Block legacy authentication",
  "state": "disabled",
  "description": "TEMPLATE: block all legacy/basic authentication (IMAP, POP, SMTP basic, old EAS). Replace REPLACE_ME exclusions, verify service accounts migrated, then enable.",
  "conditions": {
    "users": {
      "includeUsers": ["All"],
      "excludeUsers": [
        "REPLACE_ME-break-glass-account-1-object-id",
        "REPLACE_ME-break-glass-account-2-object-id"
      ],
      "excludeGroups": [
        "REPLACE_ME-service-accounts-group-object-id"
      ],
      "includeRoles": [],
      "excludeRoles": []
    },
    "applications": {
      "includeApplications": ["All"],
      "excludeApplications": []
    },
    "clientAppTypes": ["exchangeActiveSync", "other"],
    "platforms": null,
    "locations": null,
    "devices": null,
    "userRiskLevels": [],
    "signInRiskLevels": []
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["block"]
  },
  "sessionControls": null
}
```

**Before enabling, verify (in report-only):**

1. Which users *actually* use legacy auth — the sign-in log filtered on
   "Legacy authentication clients" tells you. The usual suspects: scanners
   and multifunction printers sending via SMTP basic auth, old service
   accounts on IMAP, and a handful of users with Outlook 2013 or older.
2. Migrate or exempt each one *explicitly*: service accounts move to OAuth
   SMTP (Exchange Online supports it) or get a time-boxed exclusion group
   with an expiry review date — never a permanent open exemption.
3. Exchange Active Sync with modern auth is fine; this only blocks the
   basic-auth flavor of EAS.

---

## Template C — Require compliant or hybrid-joined device for corporate apps

**Intent:** corporate applications (mail, SharePoint, the Azure portal) may
only be reached from devices the organization manages: either Intune-
compliant (`device.isCompliant -eq True`) or Hybrid Azure AD joined
(`device.trustType -eq "ServerAD"`). This implements device-based least
privilege: managed device = known-good endpoint.

> **TEMPLATE** — `state: disabled`, placeholders must be replaced.

```json
{
  "displayName": "TEMPLATE — Require managed device for corporate apps",
  "state": "disabled",
  "description": "TEMPLATE: require compliant OR hybrid-joined device for corporate apps. Replace REPLACE_ME app IDs/group, test in report-only mode, then enable.",
  "conditions": {
    "users": {
      "includeUsers": ["All"],
      "excludeUsers": [
        "REPLACE_ME-break-glass-account-1-object-id",
        "REPLACE_ME-break-glass-account-2-object-id"
      ],
      "includeRoles": [],
      "excludeRoles": [],
      "excludeGroups": []
    },
    "applications": {
      "includeApplications": ["All"],
      "excludeApplications": [
        "REPLACE_ME-public-kiosk-app-id"
      ]
    },
    "clientAppTypes": ["all"],
    "platforms": {
      "includePlatforms": ["windows", "macOS", "android", "iOS"],
      "excludePlatforms": []
    },
    "devices": {
      "deviceFilter": {
        "mode": "include",
        "rule": "device.isCompliant -eq True or device.trustType -eq \"ServerAD\""
      }
    },
    "locations": null,
    "userRiskLevels": [],
    "signInRiskLevels": []
  },
  "grantControls": {
    "operator": "OR",
    "builtInControls": ["compliantDevice", "domainJoinedDevice"]
  },
  "sessionControls": null
}
```

**Why the device *filter* plus grant controls:** the filter scopes the policy
to the device states you manage; the grant controls are what actually deny an
unmanaged device. Belt and suspenders is intentional — CA policies should be
readable by the next admin who inherits them, and redundancy in conditions
documents intent.

**Interaction with policy A:** an admin on an unmanaged device hits both —
MFA from A, device denial from C. The device denial wins (deny trumps grant).
That is correct: privileged work from unmanaged endpoints is the exact
scenario both policies exist to prevent. Admins who need emergency access
from an unmanaged device use the break-glass account (FIDO2), which is
excluded from C.

---

## Applying these templates (Graph, your own tenant only)

```powershell
# 1. Connect to your own tenant (interactive, delegated admin)
Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess"

# 2. Import one template, still disabled
$policy = Get-Content ./policies/ca-template-a.json | ConvertFrom-Json
# ... replace REPLACE_ME values ...
New-MgIdentityConditionalAccessPolicy -BodyParameter $policy

# 3. Report-only for >= 1 week, review sign-in log "Report-only" tab,
# 4. then set state to "enabled".
```

**Order of deployment:** B first (report-only — legacy auth is the
reconnaissance hole), then A (admins — the highest-value targets), then C
(device trust — the most disruptive to users, so it goes last and gets the
longest pilot). See `docs/pim-keyvault.md` for the privileged-access side
of this design.
