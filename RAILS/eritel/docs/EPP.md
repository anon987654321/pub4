# EriTel EPP integration plan

EPP is the preferred integration candidate because both Norid and ISNIC use EPP-based registry interfaces, but EriTel must confirm whether EPP is available and which extensions it requires.

## Environment separation

Required environments:

- local simulator;
- integration sandbox;
- production registry.

Production credentials must never be accepted by the local simulator.

## Conformance

Before production access, the integration should prove:

1. transport connection;
2. authentication;
3. polling;
4. domain availability;
5. domain creation;
6. domain renewal;
7. domain update;
8. deletion or restore where permitted;
9. contact operations where applicable;
10. nameserver operations;
11. DNSSEC operations where supported;
12. error handling;
13. idempotency;
14. timeout and retry behavior;
15. audit logging.

The exact conformance suite is controlled by the registry agreement.

## Security

- use dedicated credentials;
- keep secrets outside git;
- use least privilege;
- use TLS verification;
- never log credentials;
- never place credentials in process arguments;
- record correlation IDs instead of sensitive payloads where practical;
- protect replay-sensitive operations with idempotent command handling.

## Ruby boundary

The application should call Eritel::RegistryAdapter.

The adapter translates application operations into the EriTel protocol. Controllers, jobs and views must not contain EPP XML, socket handling or registry-specific credentials.

This keeps the application testable before EriTel grants access.
