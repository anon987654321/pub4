# Production Readiness

Status as of this audit: not fully production-ready until the checks below pass on the OpenBSD target.

## Shared blockers

- Rotate Rails credentials for `brgen`, `amber`, and `bsdports`; `config/master.key` was previously tracked and must be treated as exposed.
- Run each app under Ruby 3.4 with its locked bundle installed.
- Run `bin/rails db:prepare`, `bin/rails test`, `bin/brakeman`, and `bin/bundler-audit` per app.
- Deploy to the OpenBSD target and verify `/up`, TLS, host authorization, logs, database writes, background jobs, and service restart.

## brgen

Closer to production than the subapps: routes and namespaced controllers are present, SSL and host authorization are configured, and the deploy script follows the tracked-tree model.

Remaining checks:

- Verify on Ruby 3.4; local host Ruby 3.3.8 cannot run the Gemfile.
- Rotate credentials.
- Smoke test all subdomain surfaces: `tv`, `dating`, `playlist`, `takeaway`, and marketplace aliases.
- Exercise marketplace cart/order, messaging, voting, reactions, and TV live-stream flows.

## amber

Not production-ready yet.

Fixed in this pass:

- Production SSL, host authorization, and mailer host now target `amber.brgen.no`.

Remaining checks:

- Install the Rails 8 bundle and run the app test/lint/security suite.
- Rotate credentials.
- Verify wardrobe upload, Active Storage variants, AI endpoints, declutter flows, and visitor/public access boundaries.

## bsdports

Not production-ready yet.

Fixed in this pass:

- Production SSL, host authorization, mailer host, Solid Cache, and Solid Queue are configured for `bsdports.org`.

Remaining checks:

- Install the Rails 8 bundle and run the app test/lint/security suite.
- Rotate credentials.
- Verify ports import/search, watch/unwatch, comments, Solid Queue, and `/up` behind relayd.
