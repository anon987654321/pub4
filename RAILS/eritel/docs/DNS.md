# DNS and DNSSEC

This document describes the reference implementation boundary, not current EriTel policy.

## Registry responsibility

The registry decides whether a domain's nameservers and DNSSEC material are acceptable.

The partner application may preflight submissions to reduce avoidable registry errors, but the registry remains authoritative.

## Nameserver preflight

The reference preflight currently checks general hostname hygiene, uniqueness, and a conservative count range.

Those values are implementation defaults, not claims about .er requirements.

EriTel should provide the authoritative rules for:
- minimum and maximum nameservers;
- glue;
- IPv4 and IPv6;
- DNSSEC algorithms;
- DS/DNSKEY requirements;
- CD/CS records if used;
- lame delegation handling;
- polling or asynchronous validation.

## DNSSEC

The application must treat DNSSEC as typed registry data, not arbitrary text.

When EriTel specifies supported algorithms and digest types, the adapter should validate them before creating or updating a domain.

No DNSSEC key should be generated or stored by the application merely to satisfy a placeholder implementation.

## NSD

OpenBSD NSD belongs at the authoritative DNS layer only when EriTel explicitly delegates that role to the partner.

Never infer an authoritative .er zone from the public root record.
