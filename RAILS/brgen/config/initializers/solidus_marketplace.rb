# frozen_string_literal: true

# Solidus Amazon-parity path (docs/SOLIDUS_MARKETPLACE.md).
# Default: native Marketplace::* only. Enable gems with SOLIDUS_MARKETPLACE=1
# before bundle install, then run solidus:install on staging — never on a hot 1GB VPS
# with master+brgen+amber resident.

module Brgen
  module SolidusMarketplace
    module_function

    def enabled?
      ENV["SOLIDUS_MARKETPLACE"].to_s == "1"
    end

    def gems_loaded?
      defined?(Spree) || defined?(Solidus)
    end

    def mountable?
      enabled? && gems_loaded?
    end

    def status
      {
        flag: enabled?,
        gems: gems_loaded?,
        mountable: mountable?,
        fallback: "Marketplace::* native listings remain the runtime until cutover"
      }
    end
  end
end

if Brgen::SolidusMarketplace.enabled? && !Brgen::SolidusMarketplace.gems_loaded?
  Rails.logger.warn(
    "[solidus] SOLIDUS_MARKETPLACE=1 but solidus gems not loaded — " \
    "run: SOLIDUS_MARKETPLACE=1 bundle install && bin/rails g solidus:install"
  )
end
