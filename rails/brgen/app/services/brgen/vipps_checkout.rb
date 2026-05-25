# frozen_string_literal: true

module Brgen
  class VippsCheckout
    def self.initialize_payment(order_id:, amount_nok:, callback_url: nil)
      {
        order_id: order_id,
        status: "INITIATED",
        amount: amount_nok * 100,
        url: "https://api.vipps.no/v2/payments/#{order_id}"
      }
    end

    def self.verify_signature(payload, signature, key)
      OpenSSL::HMAC.hexdigest("SHA256", key, payload) == signature
    end
  end
end
