# Architecture & Design Decisions — azure-admin-implementation

Why this implementation is built the way it is: Conditional Access first, CSV-first
reporting, templates instead of live calls, and PIM-shaped privileged access.

## Why Conditional Access first

Identity is the control plane. In a cloud tenant there is no perimeter
firewall to fall back on — every request is evaluated at the identity layer,
so the identity policy *is* the perimeter. That makes Conditional Access the
highest-leverage thing an admin can design: three well-built policies (MFA
for admins, block legacy auth, managed-device requirement) close more real
attack paths than any single network control in the companion
azure-hybrid-network implementation.

Ordering matters too, and it's deliberate: **block legacy auth** goes first
in rollout because basic-auth clients can't do MFA at all — every MFA policy
you write afterward has a hole until legacy auth is dead. **Admin MFA** is
second because admin accounts are the keys to the whole directory. **Device
trust** is last because it's the most disruptive to users and needs the
longest pilot. See `docs/identity-governance.md` for the policies.

## Defense in depth, at the identity layer

Each layer assumes the one above it failed:

1. **Password** — assumed compromised (phishing works). It's the floor.
2. **MFA / authentication strength** — the wall. Policy A requires it for
   every admin sign-in, with no client-app exceptions.
3. **Client hygiene** — policy B removes the protocols that can't do MFA,
   so layer 2 has no bypass.
4. **Device trust** — policy C requires a managed endpoint, so a phished
   credential + an MFA push-bomb still can't get in from an attacker's laptop.
5. **Privileged access governance** — PIM (`docs/pim-keyvault.md`) means
   even a fully authenticated admin has no standing privileges; rights are
   activated, time-boxed, approved, and audited.
6. **Break-glass** — excluded from everything above, FIDO2-backed, and
   monitored on *any* use. The last resort is deliberately outside the
   policy stack so a policy misconfiguration can't lock out recovery.

No single layer is trusted. That's the point.

## Least privilege, operationalized

"Least privilege" is a slogan until it's a procedure. In this implementation it's three
procedures:

- **Eligible, not active** (PIM): admins hold zero standing privilege.
  Activation requires MFA + justification + ticket, expires in ≤ 8 hours.
- **Time-boxed approvals**: approvers can't approve their own role
  (separation of duties), and non-response fails closed on access reviews.
- **Secret rotation with dual-version windows** (Key Vault): consumers move
  to the new version while the old one stays valid, so least-privilege
  rotation doesn't become an outage — because a rotation procedure nobody
  trusts is a procedure nobody runs.

## Why CSV-first reporting instead of live Graph calls

`Get-MfaCoverageReport.ps1` reads an exported CSV instead of calling
Microsoft Graph, and that's a design choice, not a limitation of the implementation:

- **Auditability.** A CSV export is a point-in-time artifact: it can be
  diffed, archived, hashed, and attached to a ticket. A live query is
  gone the moment it runs.
- **Safety.** A read-only script that *can't* reach the network can't
  accidentally write to the directory, can't leak data in transit, and
  can't be one typo away from `Remove-MgUser`.
- **Reviewability.** The reviewer sees exactly the input the report was
  built from. "Trust me, I queried the tenant" is not an audit trail.

The trade-off is honest: the CSV can go stale. The mitigation is procedural
(export on a schedule, timestamp in the report header) rather than
technical. The script prints its source file and generation time for exactly
this reason.

## Why JSON templates in Graph schema (not portal screenshots)

The three Conditional Access policies are authored as JSON in the Microsoft
Graph `conditionalAccessPolicy` schema because:

- JSON is **diffable and reviewable** — a policy change is a pull request,
  not a screenshot of a portal blade.
- `state: disabled` in every template means a copy-paste can never go live
  by accident; the rollout (report-only → pilot → enabled) is a separate,
  deliberate step.
- Role references use **immutable template IDs**, not display names, so the
  policy survives renames.

## Why the Key Vault script is a guarded template

`Export-KeyVaultInventory.ps1` stops at a guard block by design. An
inventory script that touches a real vault needs the Az modules, an
authenticated session, and the *right* subscription context — three things an
implementation must not assume. The template documents the real cmdlet sequence with
TODO markers so the procedure is reviewable, while making accidental
execution impossible. The rule it encodes: **metadata only, never values** —
an inventory lists secret versions and expiry dates, never plaintext.

## Known limits (honest)

- **Nothing is deployed.** No tenant, no policies, no vault was touched in
  building this implementation, and none can be from here. Deployment needs the user's
  own Azure/Entra tenant and goes through the report-only rollout in
  `docs/identity-governance.md`.
- The MFA report's accuracy is bounded by its input CSV — garbage export in,
  garbage report out. It validates structure, not truth.
- The CA templates cover the three highest-leverage policies, not a full
  policy set (no risk-based policies, no insider-risk, no app protection
  policies — those are the next implementation).
- Break-glass and PIM approval workflows are procedures on paper here; in a
  real tenant they'd be enforced in the PIM settings blades and tested with
  a fire drill.
