# EriTel rollout

The reference deployment moves through explicit stages.

## Stage 0: repository

Rails code, simulator, tests, policy documentation and OpenBSD templates exist in git.

No production inventory entry.

## Stage 1: private development

Use the simulator.

Allowed:
- UI work;
- domain search;
- order workflows;
- lifecycle tests;
- audit tests;
- DNS preflight.

Not allowed:
- real registry credentials;
- unsolicited registry traffic.

## Stage 2: EriTel sandbox

Use only the endpoint and credentials supplied by EriTel.

Prove:
- authentication;
- availability;
- contact handling;
- domain lifecycle;
- nameserver handling;
- DNSSEC handling when supported;
- failures and timeouts;
- audit correlation.

## Stage 3: controlled pilot

Use a separate production hostname and a small participant set.

Keep registry writes narrowly scoped.

Measure:
- successful operations;
- failed operations;
- latency;
- registry errors;
- DNS validation failures;
- abuse cases;
- support load;
- reconciliation differences.

## Stage 4: production

Add the app to deployment inventory only after written authorization and the security, operational and legal gates pass.

The production host gets:
- a dedicated service account;
- protected environment file;
- relayd TLS;
- PF policy;
- rc.d supervision;
- tested backups;
- tested restore;
- incident runbook.

## Stage 5: expansion

Only after the pilot is stable should EriTel and the partner expand registrar participation, customer eligibility, geography, product surface or automation privileges.

Every expansion is a policy and contract decision, not merely a software switch.
