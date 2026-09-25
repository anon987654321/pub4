# EriTel data model

The reference schema separates registry identity, commercial transactions and operational evidence.

## Domain

The namespace object.

Stores:
- normalized name;
- lifecycle state;
- expiration;
- registry identifier.

## Registrant

The customer identity used for eligibility and ownership.

Stores:
- email;
- legal name when required;
- country;
- verification state;
- external identity reference.

## Participant

An authorized intermediary or technical provider.

Stores:
- organization name;
- role;
- authorization state;
- external identifier;
- non-sensitive metadata.

## Order

The commercial command.

Stores:
- domain;
- registrant;
- participant;
- operation;
- state;
- idempotency key;
- amount and currency;
- registry request identifier.

## Registry operation

The external system interaction.

Stores:
- order;
- operation;
- lifecycle state;
- request identifier;
- response/error metadata;
- timing.

## Audit event

The evidence trail.

Audit events are append-only in the application model.

## Principle

Commercial truth, registry truth and audit evidence are separate records. This prevents a single mutable row from becoming the source of contradictory narratives.
