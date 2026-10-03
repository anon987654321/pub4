# frozen_string_literal: true

# Optional Solidus commerce kernel. Native Marketplace::* remains the seller/order
# runtime until a deliberate dual-write and cutover on a non-1GB Postgres host.

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
