# frozen_string_literal: true

# AN106: VAPID from ENV (/etc/master.env on VPS). Views read Shared::Vapid.public_key.
Rails.application.config.x.vapid = Shared::Vapid.webpush_options