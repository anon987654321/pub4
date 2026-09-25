# EriTel registry reconciliation

An external registry call can end in an unknown state: the request may have reached the registry even when the client receives a timeout or connection reset.

The platform must preserve that uncertainty.

## State

A command with an uncertain result enters:

reconciliation

The order and registry operation remain durable.

## Operator check

The operator performs an authoritative registry lookup using the configured registry adapter.

The lookup result is recorded as an audit event.

The platform does not automatically convert:
- available -> failed;
- unavailable -> succeeded.

The meaning depends on the original operation, registry semantics and EriTel policy.

## Resolution

A human or explicitly authorized reconciliation worker resolves the durable operation after comparing:
- original command;
- registry request identifier;
- authoritative registry result;
- retry history;
- timestamps;
- participant and registrant context.

The final decision must be auditable.

## Rule

Unknown is a real state.

Never turn network uncertainty into invented registry truth.
