# EriTel security model

## Trust boundaries

The system has four distinct trust boundaries:

1. registrant browser;
2. Rails application;
3. external registry interface;
4. OpenBSD host.

The browser is untrusted input.

The Rails application is the policy and audit boundary for the partner service.

The registry is an external authority and must be treated as unavailable or inconsistent during network failure.

The OpenBSD host is the execution boundary and must not depend on an operator checkout being executable by root.

## Credentials

Registry credentials:
- never committed;
- never logged;
- never placed in process arguments;
- loaded from protected host configuration;
- rotated independently from application secrets.

## Registry commands

Every mutating registry command should have:
- an internal request identifier;
- an idempotency key where the registry supports it;
- a bounded timeout;
- explicit retry policy;
- an auditable result;
- safe handling of partial failure.

Never retry an unknown mutating result blindly.

## Audit

Record the actor, operation, domain, timestamp, external correlation identifier, and non-sensitive outcome.

Do not store full authentication secrets or unnecessary registry payloads in the audit log.

## Availability

A registry outage must not turn into invented availability.

When the external registry cannot answer, return an explicit unavailable result. Never infer that a name is free.

## Production gate

The production adapter stays disabled until:
- written authorization exists;
- protocol documentation exists;
- credentials are issued;
- sandbox testing passes;
- security review is complete.
