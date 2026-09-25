# EriTel platform demonstration

The reference application should be demonstrable without contacting a real registry.

## Scenario

1. A registrant enters an .er name.
2. DomainName normalizes the input.
3. DomainPolicy checks namespace rules.
4. The registrant is verified.
5. ParticipantAccess checks whether the request is direct, registrar or technical-partner mode.
6. Registration creates a durable pending order.
7. RegistryCommand submits the order to the simulator.
8. The simulator returns a deterministic result.
9. The order becomes active.
10. The domain becomes active.
11. Audit events record the lifecycle.

## What the demo proves

The demo is not a fake registry.

It demonstrates that the partner platform has:
- a clean registry boundary;
- policy enforcement before external calls;
- explicit authorization modes;
- durable transactions;
- idempotency;
- auditability;
- safe failure semantics.

## What is deliberately not demonstrated

The demo does not imply:
- current .er availability;
- current EriTel pricing;
- current EriTel eligibility rules;
- EriTel authorization;
- a live EPP endpoint;
- production DNS delegation.

Those become real only after EriTel supplies authoritative requirements and authorization.
