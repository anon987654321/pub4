# EriTel testing

The test strategy follows the registry boundary.

## Unit

Test:
- domain normalization;
- namespace policy;
- DNS preflight;
- participant access;
- lifecycle transitions.

## Service

Test:
- registration gating;
- registry command idempotency;
- successful lifecycle synchronization;
- failure states;
- reconciliation behavior.

## Integration

Test:
- /up;
- domain availability;
- authentication flows once implemented;
- sandbox registry adapter once EriTel supplies its protocol.

## Conformance

The future EriTel sandbox suite should be treated as authoritative for production registry integration.

## Security

Every production change should run the Rails security tooling already used elsewhere in pub4, plus the OpenBSD configuration preflight for host changes.

## Boundary rule

Simulator tests prove application logic.

They do not prove registry compatibility.
