# EriTel OpenBSD deployment

Reference infrastructure for a future authorized EriTel partner deployment.

This tree is intentionally inert with respect to the existing vm23 production configuration. Nothing here should be copied into /etc automatically, and nothing should be added to the live relayd, PF, NSD, or deployment inventory until the service has a contractual owner, hostname, network placement, and security review.

## Service boundary

Internet -> PF -> relayd -> Falcon/Rails -> SQLite

The Rails application makes outbound registry calls through an explicitly configured adapter. No inbound registry administration port is exposed by this package.

## Secret boundary

Runtime secrets belong in /etc/eritel.env or another protected store selected by the deployment owner.

The reference environment uses:
- root:eritel ownership;
- mode 0640;
- no credentials in git;
- no credentials in process arguments.

The committed .env.example contains placeholders only.

## OpenBSD responsibilities

- PF: packet filtering and narrow ingress/egress policy;
- relayd: TLS termination and HTTP forwarding;
- rc.d: process supervision;
- acme-client: certificate lifecycle;
- NSD: authoritative DNS only where EriTel delegates an agreed zone;
- local filesystem: application data and logs;
- operator procedures: backup, restore, rotation, incident response.

## Hard rules

- secrets live outside git;
- no registry credentials in process arguments;
- no direct access to EriTel systems without written authorization;
- use least privilege for service accounts;
- enable pledge/unveil where the final Ruby/Falcon process supports a safe profile;
- validate every configuration with the relevant OpenBSD tool before installation;
- stage changes before touching a live host.

Templates in this directory are examples, not production configuration.
