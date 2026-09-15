# frozen_string_literal: true

module BusinessVerificationHelper
  # Whether a request for this business is already waiting, so its owner is told
  # so rather than offered a second request the model would refuse.
  def business_verification_pending?(business)
    BusinessVerification.pending.exists?(business_type: business.class.name, business_id: business.id)
  end
end
