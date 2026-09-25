# ERITEL

## Purpose

ERITEL is the pub4 working file for exploring a lawful, transparent partnership with Eritrea Telecommunication Services Corporation (EriTel) concerning the `.er` country-code top-level domain.

The objective is not to bypass Eritrean authorities, identify private government employees, or assume that `.er` is commercially available. The objective is to establish the correct institutional contact, understand the current registry policy, and present a credible proposal for authorized international registration, registrar, technical-services, or commercialization cooperation.

## Current authoritative position

IANA's Root Zone Database currently identifies Eritrea Telecommunication Services Corporation (EriTel) as the manager of `.er`.

IANA's current delegation record lists:

- Administrative contact: General Manager, Eritrea Telecommunications Corporation
- Administrative email: `eritel@tse.com.er`
- Administrative telephone: `+291 7110591`
- Technical contact: Network Operations Center Manager
- Technical email: `erdnsmgmt@tse.com.er`
- Technical telephone: `+291 7169837`
- Registry nameservers: `er.cctld.authdns.ripe.net`, `sawanew.noc.net.er`, `zaranew.noc.net.er`

Source: IANA .ER delegation record, last updated 2025-10-28.

Do not treat third-party registrar listings as evidence that `.er` registrations are currently available.

## Strategic objective

Explore whether EriTel would consider an authorized international partnership in which EriTel retains control and policy authority over `.er`, while pub4 or an associated entity provides some combination of:

- international registrar or reseller distribution;
- registration and account infrastructure;
- API and automation;
- DNS and DNSSEC services;
- payment processing;
- customer support;
- abuse handling;
- security monitoring;
- international marketing;
- domain availability and discovery tooling;
- reporting and revenue reconciliation.

The preferred framing is:

> Help EriTel make .er more accessible internationally while preserving Eritrean ownership, policy authority, and operational control of the namespace.

No proposal should imply that pub4 owns, controls, or is entitled to the `.er` namespace.

## What must be established first

Before negotiating commercial terms, obtain authoritative answers to:

1. Who has legal and operational authority over `.er`?
2. What organization approves registrars?
3. Is direct registration under `.er` permitted?
4. Which second-level domains are available?
5. What eligibility rules apply to Eritrean and foreign registrants?
6. Can a foreign company become an authorized registrar or reseller?
7. Is there an existing registrar agreement or accreditation process?
8. What registry protocol or API is available?
9. What are the wholesale fees and payment requirements?
10. What governmental, regulatory, or ministerial approvals are required?
11. What dispute, trademark, abuse, sanctions, and law-enforcement procedures apply?
12. What technical and security requirements apply to an external partner?

Never infer an answer from an old article, registrar storefront, domain-search site, or historical ICANN report when EriTel can provide the current answer.

## Initial contact

The first contact should go to the current IANA-listed administrative address:

`eritel@tse.com.er`

The technical address should be used when the discussion reaches registry infrastructure:

`erdnsmgmt@tse.com.er`

The initial message should be short. Do not send a massive technical proposal unsolicited.

Suggested first email:

> Subject: Proposal to discuss international .er domain registration partnership
>
> Dear EriTel General Manager,
>
> I am writing to explore whether EriTel would be open to discussing an international registration and commercialization partnership for the .er country-code top-level domain.
>
> We understand that EriTel is the current manager of the .er ccTLD and that registration availability is currently limited compared with most internationally marketed ccTLDs.
>
> Our interest is to help make .er domains more accessible internationally while preserving EriTel's authority and policy control over the namespace. We can provide international registrar infrastructure, automated registration services, DNS/DNSSEC capabilities, payment processing, customer support, abuse controls, and international marketing.
>
> We would like to understand EriTel's current registration policy and whether EriTel would consider an authorized registrar, reseller, technical-services, or revenue-sharing arrangement.
>
> We would be happy to provide a short formal proposal covering the technical architecture, operating model, compliance, security, and proposed commercial structure.
>
> Could you please advise who within EriTel would be the appropriate person to discuss such a proposal with?
>
> Kind regards,
>
> [Name]
> [Company]
> [Country]
> [Website]
> [Email]
> [Telephone]

## Proposal structure

Prepare a concise proposal before the first substantive meeting.

Recommended files:

- `01_EXECUTIVE_SUMMARY.md`
- `02_BUSINESS_MODEL.md`
- `03_REGISTRY_ARCHITECTURE.md`
- `04_SECURITY.md`
- `05_DNS_DNSSEC.md`
- `06_REGISTRAR_API.md`
- `07_ABUSE_PREVENTION.md`
- `08_COMPLIANCE.md`
- `09_SUPPORT.md`
- `10_MARKETING.md`
- `11_REVENUE_MODEL.md`
- `12_IMPLEMENTATION_PLAN.md`

Keep the proposal evidence-based and avoid claiming capabilities that have not been implemented or tested.

## Commercial models to discuss

### Model A: Authorized registrar

EriTel remains registry operator and policy authority.

The partner operates an international registrar channel and pays an agreed wholesale fee per domain or transaction.

### Model B: Authorized reseller

EriTel retains the registry and registrar relationship while the partner handles international customer acquisition and support under EriTel-approved terms.

### Model C: Technical-services partnership

EriTel remains registry operator while the partner provides selected infrastructure, automation, monitoring, DNS, security, support, or API services.

### Model D: Joint international commercialization

EriTel retains namespace authority while the parties agree on an international commercial operating model and revenue-sharing structure.

Do not propose transfer or redelegation of `.er` as the opening position. Any change to ccTLD delegation is a separate matter governed by IANA/ICANN processes and the relevant local authorities.

## Domain-hack opportunity

The `.er` string has obvious potential for English-language domain hacks because many English words end in `-er`.

Examples for research only:

- `flow.er`
- `design.er`
- `play.er`
- `comput.er`
- `databas.er`
- `weath.er`

These examples do not imply that any of these names are currently registrable.

An ICANN Africa DNS study documented the historical existence of second-level namespaces including `.com.er`, `.edu.er`, `.gov.er`, `.mil.er`, `.net.er`, `.org.er`, and `.ind.er`, while also noting that their exact purposes and restrictions were not publicly documented in the study.

The same study observed that international registrars listed `.er` domains but stated that registration was not possible at the time, and identified domain-hack revenue as a potential opportunity.

This historical evidence should be used as background, not as a statement of current policy.

## Lessons from .no and .is

Norid and ISNIC provide two useful reference models rather than one template.

Norid demonstrates an accredited-registrar ecosystem: registrars are intermediaries between the registry and subscribers, enter an agreement, pass a registrar test, and integrate through documented registry services including EPP. Norid also operates technical testing and publishes registry services such as RDAP and domain availability lookup.

ISNIC demonstrates a simpler direct-access model: it has no official registrars, permits sufficiently capable registrants and DNS providers to work directly with the registry, and offers EPP access after competency is demonstrated in a sandbox.

The EriTel reference architecture should therefore support three policy-controlled operating modes:

1. Direct: an eligible registrant uses an EriTel-operated registration interface.
2. Registrar: an accredited international registrar acts as the customer-facing intermediary.
3. Technical partner: an approved DNS or service provider receives only the registry access required for its documented role.

Common machinery should remain in the registry core: explicit policy, authentication, EPP/API access, DNS validation, DNSSEC support where available, audit events, abuse workflows, lifecycle state transitions, reporting, and a sandbox/test environment.

The software should make these modes configurable policy choices rather than hard-coded assumptions. EriTel decides which modes exist and who may use them.

Norid's current public statistics show 887,043 .no domains and 263 registrars, illustrating the scalability of an intermediary model. ISNIC's current EPP documentation shows a production EPP service, a sandbox, and competency requirements, illustrating how a smaller registry can expose a controlled automation path without creating a conventional registrar hierarchy.

These are reference architectures, not claims about what EriTel should adopt or what .er currently permits. Current .er policy must come from EriTel and the relevant Eritrean authorities.

## Technical architecture

Preferred conceptual architecture:

```
Registrant
    |
    v
International Registrar / Partner
    |
    | authorized registry protocol / API
    v
EriTel Registry
    |
    v
.er Authoritative DNS
```

Security and governance principles:

- EriTel remains the authoritative registry operator unless an explicit agreement states otherwise.
- No attempt is made to bypass registry policy.
- Registry credentials are never hard-coded.
- Registry and registrar credentials use least privilege.
- All registration operations are auditable.
- DNSSEC is preserved and validated where supported.
- Abuse reports have a defined escalation path.
- Financial reconciliation is independently auditable.
- Customer data is minimized and protected.
- Any sanctions, export-control, AML/KYC, privacy, or other legal requirements are reviewed by qualified counsel before launch.

## Engagement sequence

### Phase 1: Verify

- Confirm the current IANA delegation record.
- Confirm EriTel contact details.
- Establish whether the listed addresses are still active.
- Document all public registration-policy information.
- Separate current facts from historical reports.

### Phase 2: Contact

- Send the short administrative email.
- Wait a reasonable business period.
- Send one concise follow-up if necessary.
- Ask EriTel to identify the correct institutional counterpart.
- Do not spam multiple officials or departments.

### Phase 3: Discover

Hold an introductory meeting.

Primary goal: understand EriTel's current policy, technical architecture, authority structure, and openness to partnership.

No pricing commitment should be made before the operating model is understood.

### Phase 4: Propose

Submit the concise partnership proposal.

Include:

- problem;
- opportunity;
- proposed role;
- architecture;
- security;
- compliance;
- support;
- economics;
- implementation plan;
- governance.

### Phase 5: Validate

Before implementation:

- obtain written authorization;
- execute appropriate agreements;
- establish technical contacts;
- establish abuse and legal escalation;
- test registration in a controlled environment;
- establish billing and reconciliation;
- verify DNS/DNSSEC behavior;
- verify registrar and registry responsibilities.

### Phase 6: Launch

Begin with a controlled pilot.

Measure:

- registrations;
- renewals;
- failed transactions;
- abuse reports;
- support volume;
- DNS incidents;
- payment failures;
- revenue;
- customer acquisition;
- registry/API reliability.

Expand only after the pilot is stable and EriTel's requirements are satisfied.

## Contact log

Maintain a factual log here.

| Date | Contact | Channel | Purpose | Response | Next action |
|---|---|---|---|---|---|
| TBD | EriTel General Manager | Email | Initial partnership inquiry | TBD | TBD |

Do not store unnecessary personal information about individual government employees.

## Evidence

IANA currently identifies EriTel as the `.er` ccTLD manager and publishes the administrative and technical contact details above.

ICANN's Africa DNS research provides useful historical context about Eritrea's ccTLD ecosystem and the potential commercial opportunity, but its older observations must not be treated as current registry policy.

Primary sources:

- IANA Root Zone Database: https://www.iana.org/domains/root/db/er.html
- IANA .ER WHOIS record: https://www.iana.org/whois?q=.er
- ICANN Africa DNS Market Study: https://www.icann.org/en/system/files/files/africa-domain-name-industry-study-28may24-en.pdf

## Working rules

1. Use official sources first.
2. Treat IANA as the authoritative public delegation record.
3. Treat EriTel as the authority on current registration policy.
4. Never imply authorization that has not been granted.
5. Never contact private individuals through non-public channels for the purpose of obtaining access.
6. Never attempt technical access to EriTel systems without explicit authorization.
7. Never bypass registry restrictions.
8. Separate historical evidence from current facts.
9. Put legal/compliance questions to qualified counsel.
10. Preserve Eritrean namespace authority in the proposed operating model.
11. Prefer a small pilot over an irreversible commitment.
12. Keep every claim in the proposal traceable to evidence or explicitly marked as a proposal.

## Success condition

Success is not “obtaining .er.”

Success is reaching a documented, authorized understanding with EriTel about whether and how an international partnership can operate, followed by a technically secure and legally compliant pilot if EriTel chooses to proceed.
