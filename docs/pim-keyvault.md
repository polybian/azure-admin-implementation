# Privileged Identity Management (PIM) + Key Vault — Runbook

Procedural runbook for administering privileged access in Microsoft Entra ID
and for rotating secrets in Azure Key Vault. Templates and procedures only —
nothing here executes against a real tenant or vault. Written for the admin
who inherits this at 2 a.m. during an incident.

---

## Part 1 — PIM: eligible vs. active assignments

**The core idea:** nobody *holds* admin rights day-to-day. Admins are
*eligible* for a role and must **activate** it — with MFA, a ticket number,
and a time limit — when they actually need it.

| | Eligible assignment | Active assignment |
|---|---|---|
| What it is | Standing permission to *request* a role | The role is live on your account right now |
| Day-to-day state | No admin privileges | Full admin privileges |
| How you get it | Assigned by a PIM admin, or self-requested with approval | You activate an eligible assignment (MFA + justification + ticket) |
| Duration | Persistent until removed (reviewed quarterly) | Time-boxed: max 8 hours per activation (configurable, default 8h) |
| Use for | Everyone who might ever need the role | Almost nobody, except break-glass |

**Rule of thumb:** if an account has an *active* Global Administrator
assignment at 3 p.m. on a Tuesday with no change ticket, something is wrong.
Eligible = "can become admin"; active = "is admin right now".

### Activation workflow (what the admin experiences)

1. Admin opens Entra admin center → Identity governance → PIM → "My roles".
2. Clicks **Activate** on the eligible role → enters:
   - **Duration** (default 8 hours; cannot exceed the role's max setting)
   - **Justification** (free text: *what* you're doing and *why*)
   - **Ticket number** (the change/incident ticket — mandatory for Global Admin)
3. Entra prompts for **MFA** (or authentication strength per policy).
4. If the role requires **approval**, the designated approver(s) get notified
   and must approve within the SLA (recommended: 30 minutes for production
   roles, 4 hours for dev). No approval = no activation = request expires.
5. On expiry, the role is revoked automatically. The full chain — who, when,
   why, ticket, approver — lands in the **PIM audit log** (retained 1 year).

### Approval workflow design (recommended)

| Role | Activation requires | Approver | Max duration | Ticket required |
|---|---|---|---|---|
| Global Administrator | Approval + MFA + ticket | 2nd Global Admin (not the requester) | 8 hours | Yes |
| Privileged Authentication Administrator | Approval + MFA + ticket | Global Admin | 8 hours | Yes |
| Conditional Access Administrator | Approval + MFA | Global Admin or CA Admin | 8 hours | Yes |
| User Administrator | MFA + ticket (no approval) | — (self-activate, audited) | 8 hours | Yes |
| Helpdesk Administrator | MFA (no approval) | — (self-activate, audited) | 8 hours | Recommended |

**Approver hygiene:** approvers must not be eligible for the *same* role
they approve (separation of duties). Approvers get a weekly digest of the
requests they approved so "approve fatigue" is visible.

### Access reviews (cadence)

Access reviews answer one question on a schedule: *"does this person still
need this access?"* PIM access reviews are configured per role:

- **Privileged roles** (Global Admin, Privileged Auth Admin, CA Admin):
  **quarterly**, owner = the tenant's security lead. Auto-apply: **deny**
  if the reviewer doesn't respond (fail-closed — access is the thing being
  removed, so a non-response must remove it).
- **Standard admin roles** (User Admin, Helpdesk, Billing): **semi-annual**.
- **Guest users with any admin eligibility**: **monthly** — guests should
  almost never hold eligible admin roles; the review exists to catch it.
- **Reviewers**: the role's current holders review each other, plus the
  security lead as fallback. Self-review is disabled where possible
  (reviewers cannot approve their own continued access).

**What happens on a "deny":** the eligible assignment is removed immediately,
the decision is logged to the audit log, and the ex-holder gets an email
explaining the removal and how to re-request. Re-requests go through the
approval workflow again — there is no "undo".

### Break-glass accounts (the exception to everything)

- Two cloud-only accounts (`*.onmicrosoft.com`), **excluded from all CA
  policies and from PIM** (they must work when PIM itself is broken).
- Each has a **FIDO2 hardware key**; credentials sealed in the company safe,
  not in a password manager anyone logs into with Entra.
- **Monitored, not used:** an alert fires on *any* sign-in to either account
  (see the monitoring note in `docs/architecture.md`). Usage triggers an
  automatic post-incident review.
- Passwords rotated **semi-annually**; rotation is a scheduled task in the
  change calendar, not "when someone remembers".

---

## Part 2 — Key Vault secret-rotation procedure

**Scope:** application secrets, API keys, and certificates stored in Azure
Key Vault. This is the *procedure*; the inventory template script lives at
`scripts/Export-KeyVaultInventory.ps1` (template only — it does not touch a
real vault).

### Rotation schedule

| Secret type | Rotation cadence | Notes |
|---|---|---|
| Service principal client secrets | **90 days** | Automate with the vault's rotation policy where the issuer supports it |
| API keys (third-party) | **90 days** or per vendor guidance | Coordinate with the vendor's own rotation window |
| TLS certificates | **Before 30 days to expiry** | Alert at 60/30/7 days; rotation is a change ticket |
| Database connection strings | **180 days** | Rotate app-side and DB-side in the same window |
| Break-glass-adjacent credentials | **Semi-annually** | Same calendar as the Entra break-glass rotation |

### Rotation steps (per secret)

1. **Plan.** Identify every consumer of the secret (apps, pipelines, runbooks)
   from the vault's access logs and the CMDB. A rotation that misses a
   consumer is an outage.
2. **Stage the new value.** Generate the new secret *in the vault* as a new
   version (never overwrite-and-delete: keep the old version enabled during
   the transition). For Key Vault rotation policies, configure
   `expiryTime` + `notifyBeforeExpiry`.
3. **Deploy consumers.** Roll the new version out to all consumers. Support a
   **dual-secret window** where both versions are valid (old version stays
   enabled) — typically 24–72 hours for APIs, one deployment cycle for apps.
4. **Verify.** Confirm every consumer authenticates with the new version:
   check application logs and the vault's secret-version usage. The old
   version's "last used" timestamp going quiet is your signal.
5. **Disable the old version.** Disable (don't delete) the old secret version.
   Wait one full monitoring cycle (24h) — if nothing breaks, the rotation is
   complete.
6. **Purge only per policy.** Deleted versions stay in soft-delete for the
   vault's retention period (default 90 days). Purge earlier only with
   security-lead sign-off; the retention window is your rollback.

### Who approves

- **Standard rotation** (service secrets, API keys, certs): the **application
  owner** approves the change ticket; the **platform/identity admin**
  executes. Two people, always — the executor never approves their own rotation.
- **Emergency rotation** (suspected compromise): the **security lead** can
  authorize verbally (incident bridge), followed by a retroactive ticket
  within 24 hours. Speed beats paperwork when a secret is burned.
- **Break-glass-adjacent**: **CISO/security lead + one witness**; both sign
  the sealed-envelope log.

### Audit trail (what must be provable afterward)

Every rotation must leave these artifacts, in this order of authority:

1. **Key Vault diagnostic logs** → Log Analytics: `SecretGet`, `SecretSet`,
   `SecretVersion` operations with caller identity and timestamp. This is the
   source of truth — it cannot be edited from inside the tenant's normal
   admin roles (diagnostic settings changes are themselves logged).
2. **Change ticket** with approver, executor, dual-secret window dates, and
   the verification evidence (log excerpts, not the secret values).
3. **Version metadata in the vault**: each version carries `tags` —
   `rotated-by`, `ticket`, `rotation-date`. Secrets themselves never appear
   in tickets, chat, or email.
4. **Quarterly attestation**: the security lead signs off that every secret
   past its rotation cadence was rotated or has a documented exception with
   an expiry date. Exceptions expire; they don't linger.

### What "done" looks like

A rotation is done when: the old version is disabled, all consumers are on
the new version, the ticket is closed with evidence, and the next rotation
date is on the calendar. If any of those is missing, it's not done — it's
"rotated, probably".
