# EriTel policy framework

This is a proposed policy shape, not current EriTel policy.

## Policy layers

### Namespace policy

Defines:
- which labels exist;
- which second-level zones exist;
- reserved names;
- IDN rules;
- eligibility;
- geography requirements;
- registration periods;
- transfer rules;
- deletion and redemption rules.

### Participant policy

Defines:
- direct registrant access;
- registrar accreditation;
- reseller authorization;
- DNS provider registration;
- technical competency requirements;
- contracts;
- suspension and termination.

### Technical policy

Defines:
- EPP or API requirements;
- authentication;
- certificate handling;
- IP allowlisting if required;
- nameserver requirements;
- DNSSEC rules;
- rate limits;
- maintenance windows;
- sandbox conformance.

### Data policy

Defines:
- required registration data;
- verification requirements;
- public disclosure;
- RDAP fields;
- retention;
- access logging;
- lawful disclosure;
- privacy and security obligations.

### Abuse and dispute policy

Defines:
- abuse intake;
- evidence requirements;
- escalation;
- suspension and hold states;
- trademark and rights complaints;
- appeals;
- law-enforcement requests;
- emergency procedures.

### Change policy

Policy changes should be versioned, dated, reviewed and published before becoming effective, subject to the governing legal and institutional framework.

## Lifecycle

A useful implementation model is:

pending
active
warning
hold
parked
deleted

The actual meanings, transition triggers and retention periods must be set by EriTel.

## Core principle

Code should enforce published policy. Code should not become unpublished policy.
