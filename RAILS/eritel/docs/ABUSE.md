# Abuse and dispute workflow

This is a proposed operating boundary. EriTel defines the authoritative policy.

## Intake

Every report receives:
- case identifier;
- timestamp;
- reporter category;
- affected domain;
- evidence location;
- requested action;
- urgency.

## States

received
triaged
awaiting-evidence
referred
actioned
appealed
closed

## Registry actions

Possible actions include:
- no action;
- warning;
- technical remediation request;
- temporary hold;
- suspension;
- deletion where authorized.

The Rails application records the action requested or taken. It must not invent registry authority.

## Emergency path

Emergency handling should have:
- named EriTel contact;
- severity definitions;
- out-of-hours contact;
- evidence preservation;
- decision logging;
- post-incident review.

## Privacy

Collect only the information needed to investigate and route a case. Do not publish reporter data by default.
