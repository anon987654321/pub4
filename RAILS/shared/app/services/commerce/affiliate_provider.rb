# frozen_string_literal: true

module Shared
  module Commerce
    # AffiliateProvider — abstract interface for affiliate networks.
    # Every provider must implement the contract for discovery, conversion, and verification.
    class AffiliateProvider
      def fetch_products(category:, limit: 10)
        raise NotImplementedError, "#{self.class} must implement #fetch_products"
      end

      def verify_conversion(conversion_id:)
        raise NotImplementedError, "#{self.class} must implement #verify_conversion"
      end

      def canonical_url(product_id:)
        raise NotImplementedError, "#{self.class} must implement #canonical_url"
      end

      def provider_id
        raise NotImplementedError, "#{self.class} must implement #provider_id"
      end
    end
  end
end
