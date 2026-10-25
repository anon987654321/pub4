# frozen_string_literal: true

require "test_helper"

class ShareDraftCleanupJobTest < ActiveSupport::TestCase
  test "removes expired private drafts and retains current ones" do
    city = City.find_by(domain: "brgen.no") || City.create!(
      name: "Bergen", slug: "bergen-share-draft-test",
      domain: "brgen.no", country_code: "NO", locale: "nb", currency: "NOK"
    )
    user = User.create!(
      email_address: "draft-cleanup-#{SecureRandom.hex(4)}@brgen.no",
      password: "password12345", city: city
    )
    expired = ShareDraft.create!(
      user: user, city: city, title: "Expired", content: "",
      expires_at: 1.hour.ago
    )
    current = ShareDraft.create!(
      user: user, city: city, title: "Current", content: "",
      expires_at: 1.hour.from_now
    )

    ShareDraftCleanupJob.perform_now

    refute ShareDraft.exists?(expired.id)
    assert ShareDraft.exists?(current.id)
  end
end
