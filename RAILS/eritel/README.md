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

See ERITEL.md for the partnership plan and evidence rules.
