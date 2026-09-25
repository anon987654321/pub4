# Social Browser

## Canonical contract


## Purpose

Social Browser is a governed browser-automation plugin for authorized social
accounts. It separates browser mechanics from MASTER's policy and approval
boundary.

## Inputs

- Explicitly authorized account/session state.
- A bounded browser action requested by MASTER.
- The plugin actions exposed by `social_browser.rb`.

## Outputs

- Structured observation of the requested page/action.
- Explicit success or failure for each browser operation.
- No claim of action completion unless the browser reports completion.

## Invocation

The entrypoint is `MASTER/plugins/social_browser/social_browser.rb`.
MASTER should dispatch actions through the plugin boundary rather than
embedding browser-specific logic in core code.

## Architecture

`plugin.yml` is the manifest and `social_browser.rb` is the implementation
boundary. The plugin remains outside MASTER core so browser dependencies and
site-specific behavior do not leak into the governance runtime.

## Data and state

Browser sessions and credentials are external state. They must not be committed
to the repository. Persist only the minimum metadata needed for an auditable
authorized action.

## Security boundary

Only operate on accounts and content the operator is authorized to control.
Keep credentials out of logs and prompts, validate destinations, bound uploads
and downloads, and require explicit confirmation for consequential actions such
as posting, deleting, following, messaging, or changing account settings.

## Validation

Unknown actions, missing sessions, invalid destinations, stale pages, and
browser errors must remain explicit failures. Never report an action as done
because a click was attempted.

## MASTER integration

Social Browser is a plugin, not a generic tool: it extends MASTER through a
manifested capability boundary and remains independently replaceable.

## Failure modes

Authentication expiry, consent/authorization failure, browser startup failure,
site navigation failure, DOM drift, rate limiting, or ambiguous post-action
state must all be visible to the caller.

## Examples

```sh
ruby MASTER/plugins/social_browser/social_browser.rb --help
```
