# Air Superiority

## Purpose

Air Superiority is a MASTER plugin for defensive local observation of Wi-Fi and
Bluetooth environments. It keeps a local known-device baseline so an operator
can compare an observed scan with what was previously known.

## Inputs

- Local Wi-Fi and Bluetooth observation data.
- An optional local baseline of known devices.
- Plugin actions declared by `plugin.yml`: `status` and `scan`.

## Outputs

- A deterministic status report.
- A scan result describing observed devices and baseline differences.
- No remote telemetry is required by the plugin contract.

## Invocation

The plugin entrypoint is `MASTER/plugins/air_superiority/air_superiority.rb`.
MASTER dispatches it as a governed plugin rather than treating it as a
core tool.

## Architecture

`plugin.yml` declares identity, version, entrypoint, and supported observation
actions. `air_superiority.rb` owns command routing; `analyzer.rb` contains
observation/baseline analysis; `models.rb` contains the small shared data
objects.

## Data and state

The baseline is local operator state. It must be explicit about where it is
read and written and must never be confused with live radio observations.

## Security boundary

Observation is passive/defensive. Do not add packet injection, credential
capture, deauthentication, exploitation, or unauthorized device interaction.
Treat discovered identifiers as potentially sensitive local data and avoid
shipping them to a third party.

## Validation

The plugin must boot without network credentials, parse its manifest, reject
unknown actions, and keep scan failures explicit. A missing radio interface
must report an unavailable observation rather than fabricate a result.

## MASTER integration

The plugin lives under `MASTER/plugins` because it extends MASTER's capability
surface without becoming part of the core tool registry.

## Failure modes

Unsupported adapter, permission denial, malformed baseline, unavailable radio
interface, or invalid action must be observable and non-successful.

## Examples

```sh
ruby MASTER/plugins/air_superiority/air_superiority.rb status
ruby MASTER/plugins/air_superiority/air_superiority.rb scan
```
