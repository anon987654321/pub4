# EriTel OpenBSD operating contract

The reference deployment follows the existing pub4 OpenBSD model but remains isolated until an actual service is authorized.

## Network

Internet -> PF -> relayd -> Falcon -> Rails

Registry traffic is outbound only.

No registry administration listener is exposed to the public Internet.

## Process

Falcon runs as the unprivileged eritel service account.

Secrets are loaded from /etc/eritel.env.

The service is supervised through rc.d.

## TLS

relayd terminates public TLS.

acme-client manages the certificate lifecycle after a real hostname exists.

## DNS

NSD is used only where EriTel explicitly delegates an authoritative DNS role.

Do not create an authoritative .er zone from guessed information.

## Hardening

The final production profile should include:

- PF default deny with explicit exceptions;
- relayd health checks;
- rc.d process supervision;
- filesystem permissions reviewed before launch;
- pledge and unveil where compatible with the final process;
- no secrets in git;
- no secrets in process arguments;
- auditable backups;
- tested restoration;
- centralized incident and abuse runbooks.

## Resource profile

The production target should assume a small OpenBSD host unless EriTel specifies otherwise.

Keep the first deployment deliberately boring:
- one Rails process group;
- one SQLite database with tested backups;
- Solid Queue for background work only where required;
- outbound registry connections from the application;
- relayd as the only public application listener.

Scale horizontally only when measured load or availability requirements justify it.

## Deployment gate

The service moves from reference to production only when all of the following exist:

- named EriTel counterpart;
- written authorization;
- approved hostname;
- approved network placement;
- approved registry protocol;
- approved credentials;
- completed sandbox testing;
- legal and security review;
- backup and recovery test;
- production inventory entry.

Until then, the files in OPENBSD/eritel are templates, not installation instructions.
