# Shared Rails wiring notes

This file describes how each app should connect the shared layer until `DEPLOY/rails/shared` is packaged as a real Rails engine or gem.

## Copy shared files

Run from `DEPLOY/rails`:

```sh
sh shared/install_frontend_baseline.sh amber
sh shared/install_frontend_baseline.sh brgen
sh shared/install_frontend_baseline.sh baibl
sh shared/install_frontend_baseline.sh blognet
sh shared/install_frontend_baseline.sh bsdports
sh shared/install_frontend_baseline.sh hjerterom
```

## Social endpoints to mount in each app

Add app-local routes that point to the copied shared controllers:

- one endpoint that calls `Shared::ReactionsController#create`
- one notifications index endpoint
- one notification update/read endpoint
- one notifications read-all endpoint
- one review-case create endpoint
- one review-case update endpoint

Keep the path names product-specific where needed:

- Brgen: reaction, notifications, review cases
- Amber: item/outfit reactions, notifications, review cases
- Blognet: article reactions, notifications, review cases
- Baibl: annotation reactions, notifications, review cases

## Model inclusion

Include shared concerns in app models deliberately:

```ruby
class Post < ApplicationRecord
  include Shared::Reactable
end

class Outfit < ApplicationRecord
  include Shared::Reactable
end
```

Only include `Shared::Followable` on models that users should be able to subscribe to.

## Signed target IDs

Shared controllers expect signed global IDs for targets. Views should use:

```ruby
record.to_sgid.to_s
```

This keeps polymorphic user-facing action targets tamper-resistant.

## Next hardening

- Add app-local authorization before review updates.
- Add tests for every mounted route.
- Replace copy/install with a Rails engine once app structure stabilizes.
