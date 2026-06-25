# frozen_string_literal: true

# CSP frame-ancestors whitelists brgen/amber embeds; Rails 8 default X-Frame-Options blocks them.
Rails.application.config.action_dispatch.default_headers.delete("X-Frame-Options")