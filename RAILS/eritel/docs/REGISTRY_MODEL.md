# EriTel registry operating model

## Purpose

The reference design supports three operating modes. EriTel selects which modes are legally and operationally available.

## Mode: direct

The registrant interacts directly with the EriTel registration service.

Architecture:

registrant -> EriTel registration service -> registry

Useful characteristics:
- simple registry relationship;
- fewer intermediaries;
- direct control over customer workflow;
- suitable for technically capable registrants.

Reference: ISNIC permits registrants to contact its registry directly and has no official registrar layer.

## Mode: registrar

An approved registrar provides the customer-facing service.

Architecture:

registrant -> accredited registrar -> EriTel registry

Useful characteristics:
- international distribution;
- competition between customer-facing providers;
- registrar-specific support and billing;
- clear separation between registry policy and retail service.

Reference: Norid requires subscribers to use registrars and operates an application, agreement, testing and integration path.

## Mode: technical partner

A DNS provider or technical service receives narrowly scoped registry access.

Architecture:

registrant -> partner service -> EriTel registry

The partner must not receive privileges that are unnecessary for its role.

Useful characteristics:
- DNS hosting ecosystem;
- automation;
- controlled operational delegation;
- less pressure on the registry to build every external service itself.

## Shared registry core

Regardless of mode, the registry-facing core should expose:

- policy evaluation;
- identity and authorization;
- domain lifecycle;
- nameserver validation;
- DNSSEC data where supported;
- EPP or another documented API;
- audit events;
- abuse and dispute workflows;
- billing and reconciliation;
- RDAP or equivalent registration-data access;
- availability checks;
- sandbox and conformance testing;
- operational metrics.

The public API must expose policy outcomes and errors without leaking internal credentials or unnecessary customer data.

## Design rule

Do not hard-code Norid policy or ISNIC policy into the EriTel application.

Borrow architecture, not rules.

Every EriTel-specific restriction belongs in explicit configuration or documented policy once EriTel confirms it.
