# MASTER personal privacy contract

MASTER's personal-device mode is default-deny. This document describes required behavior; it does not claim that every hardware adapter already enforces it.

## Required behavior

- No microphone, wake-word, camera, location, contacts, messages, financial data, external messaging, purchase, deployment, or destructive capability is enabled merely by installing or opening MASTER.
- Each capability requires a distinct, explicit confirmation by the relevant account/device owner. Silence, proximity, inferred identity, a relationship, prior unrelated approval, or another person's approval is not consent.
- Grants name a purpose and may expire. Revoke must take effect before the next capability use. Adapters must check the permission immediately before the effect, not only at startup.
- MASTER must also request the Android operating-system permission where applicable. The local permission ledger never substitutes for OS permissions.
- Show a truthful, visible listening/speaking/recording state. Do not perform hidden background recording. Provide an immediate stop/interrupt control and a way to inspect recent capability events.
- Personal memory is opt-in, locally stored under `.master/`, inspectable, correctable, exportable and deletable by its owner. Do not place personal profiles in public repository configuration. Conversation retention and opt-out deletion rules remain in `Ground::ConversationStore`.
- Financial features begin read-only and informational. No transfer, trade, payment, credit application or other consequential financial action without a separate, fresh, transaction-specific approval and an independently verified summary of amount, recipient and consequences.
- Companion features must not claim personhood, exclusivity, romantic reciprocity, professional credentials or guaranteed protection. They must not pressure a person to share data or use MASTER. The person can decline or stop without affecting anyone else's access.
- A nearby person is not automatically the owner. Pairing, changing owner, releasing a device, and sharing a profile require an explicit owner-controlled flow. Separate people's memories and permissions.
- Logs must be understandable and privacy-preserving. Do not log raw credentials, full payment details or unrelated private content. Retain only bounded event metadata necessary for review.

## Ruby policy primitive

`Master::Ground::PersonalPermissions` stores grants in the local `.master/permissions/personal.json` ledger with restrictive file modes, explicit scope, purpose, actor, timestamp, optional expiry, revocation and a bounded audit trail. Unknown scopes fail closed. It is a policy primitive, not proof that a microphone, Android permission, memory store, financial adapter or message sender has already been wired to consult it.

Before enabling any such adapter, add a regression test proving the adapter checks the ledger immediately before acting, denies by default, respects revocation/expiry, and still requires native OS permission. If the permission store is unavailable or malformed, deny the operation. A user interface must not represent an unimplemented check as protection.

## Verification status

Run `ruby -Itest test/test_personal_permissions.rb` from `MASTER/`. Then add adapter-level tests and real Android/Termux checks. Source existence alone is not a PASS.
