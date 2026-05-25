# frozen_string_literal: true

module Brgen
  class Anonymizer
    def self.mask_id(user_id, context_salt)
      OpenSSL::HMAC.hexdigest("SHA256", context_salt, user_id.to_s)[0..15]
    end

    def self.verify_mask(masked_id, user_id, context_salt)
      mask_id(user_id, context_salt) == masked_id
    end
  end
end
