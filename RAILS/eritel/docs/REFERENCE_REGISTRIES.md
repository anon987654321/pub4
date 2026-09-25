# Reference registries

These references describe architecture patterns only. They do not establish current .er policy.

## Norid

Norid uses an accredited registrar model. Registrars are intermediaries between the registry and subscribers. The path includes an agreement, a registrar test, test environments, and EPP integration.

Useful ideas for EriTel:
- explicit registrar agreement;
- competency test before production access;
- separate registrar and registry responsibilities;
- EPP sandbox;
- availability service;
- RDAP;
- documented DNS and DNSSEC integration;
- operational communication channel.

Source:
https://teknisk.norid.no/en/bli-forhandler/
https://teknisk.norid.no/en/integrere-mot-norid/
https://teknisk.norid.no/en/administrere-domenenavn/oversikt-over-verktoy-og-tjenester/

## ISNIC

ISNIC uses a direct registry model rather than a conventional shared registry/registrar model. Technically capable registrants and DNS providers can interact directly with the registry. EPP access is available through a sandbox and requires demonstrated competency.

Useful ideas for EriTel:
- direct access as an explicit policy option;
- DNS provider participation;
- sandbox before production;
- simple competency gate;
- narrowly scoped technical access;
- automated DNS compliance testing.

Source:
https://www.isnic.is/en/api/epp
https://www.isnic.is/en/domain/test

## Combined lesson

EriTel does not need to choose one historical model wholesale.

The software can support:
- direct registrants;
- accredited registrars;
- technical DNS/service partners.

EriTel's published policy and agreements decide which modes are enabled.
