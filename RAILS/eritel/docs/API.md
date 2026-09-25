# EriTel partner API

The public application API is intentionally smaller than the internal registry adapter.

## Public endpoints

GET /up
Returns application health.

GET /domains/check?domain=example.er
Runs local policy checks and then the configured registry availability operation.

Future authenticated endpoints may cover:
- registrant;
- domains;
- orders;
- renewals;
- registrar administration;
- abuse cases;
- reports.

## Registry boundary

The Rails application must keep EPP XML, registry-specific transport, credentials and retry logic inside the registry adapter.

Controllers call application services.

Application services call the registry gateway.

The gateway selects the authorized adapter.

## Failure semantics

- invalid input -> 4xx;
- local policy rejection -> 422;
- registry unavailable -> 503;
- successful registry result -> 200;
- unknown registry result for a mutating command -> explicit pending/reconciliation state.

Never convert an external timeout into success or availability.
