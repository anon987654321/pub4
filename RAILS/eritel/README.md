# EriTel Rails partner platform

This tree is a reference deployment for an authorized international .er registrar, reseller, or technical-services partnership.

It is intentionally not part of the active three-app production inventory. Do not add it to apps.yml until an actual EriTel operating agreement, hostname, port, registry protocol, and deployment owner exist.

## Boundary

The Rails application owns the customer-facing and partner-facing workflow:

registrant -> account -> eligibility -> order -> payment -> registry adapter -> reporting

The registry itself remains outside this tree. The only integration boundary is Eritel::RegistryAdapter.

Until EriTel provides an authorized registry protocol and credentials, the application must use Eritel::RegistrySimulator in development/test and must fail closed for production registry writes.

## Intended capabilities

- domain availability search;
- registrant accounts and verification;
- domain orders and renewals;
- registrar/reseller administration;
- payment abstraction;
- registry adapter boundary;
- DNS/DNSSEC status tracking;
- abuse and dispute intake;
- audit events;
- financial reconciliation;
- operational health;
- bilingual-ready UI and API.

## OpenBSD shape

Internet -> PF -> relayd -> Falcon/Rails -> SQLite/Solid stack

The registry connection is outbound from the application only and is disabled until explicitly configured.

## Inventory rule

This is a partner deployment package, not a fourth public pub4 application. It must not be added to the live RAILS apps.yml, live OPENBSD/deploy_inventory.json, or production relayd configuration merely because the code exists.

## Verification

Before any external launch:

1. establish the legal and operational counterpart at EriTel;
2. obtain written authorization;
3. document the registry protocol and test endpoint;
4. configure secrets outside git;
5. run Rails security and dependency checks;
6. test the registry adapter against an authorized non-production endpoint;
7. add the service to production inventory only after the above are complete.

## Documentation

- docs/REFERENCE_REGISTRIES.md — Norid and ISNIC patterns.
- docs/REGISTRY_MODEL.md — direct, registrar and technical-partner modes.
- docs/POLICY.md — proposed policy layers.
- docs/EPP.md — sandbox and production integration boundary.
- docs/API.md — application API boundary.
- docs/DNS.md — nameserver and DNSSEC boundary.
- docs/SECURITY.md — trust, secrets, audit and failure handling.
- docs/ABUSE.md — abuse and dispute workflow.
- docs/COMMERCIAL.md — transaction and settlement model.
- docs/OPERATIONS.md — OpenBSD operating contract.
- docs/ROLLOUT.md — staged deployment.
- docs/REGISTRATION.md — guarded registration workflow.
- docs/RECONCILIATION.md — unknown-result handling.
- docs/PARTICIPANTS.md — accreditation boundary.
- docs/DATA_MODEL.md — data model.
- docs/DEMO.md — registry-free demonstration path.
- docs/TESTING.md — test layers.

See ERITEL.md for the partnership plan and evidence rules.

## Reference registry models

The design deliberately combines lessons from the Norwegian and Icelandic ccTLD operating models.

Norid pattern:
- accredited registrars;
- registrar agreement and competency testing;
- EPP integration;
- DNS and DNSSEC validation;
- public RDAP and availability services;
- registry remains neutral while registrars handle customer-facing work.

ISNIC pattern:
- direct registrant access is possible;
- no conventional official registrar layer;
- DNS service providers can receive a defined technical role;
- EPP access follows demonstrated competency;
- sandbox and production environments are separated.

The EriTel implementation supports all three as policy modes rather than assuming that one model is correct:
- direct;
- accredited registrar;
- technical partner.

See docs/REGISTRY_MODEL.md, docs/POLICY.md and docs/EPP.md.

## Safety boundary

The reference application never guesses a registry protocol. The adapter is intentionally incomplete until EriTel supplies an authorized interface specification, endpoint, credentials, and operating agreement.

A simulator is acceptable for product development. Production registry writes are not.
