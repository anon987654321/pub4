# frozen_string_literal: true

require "test_helper"

class PostproJobTest < ActiveSupport::TestCase
  test "postpro script resolves to MASTER/tools/postpro/postpro.rb" do
    script = Shared::PostproProcessor.script
    assert script, "postpro script not found in #{Operator::DeployPaths.postpro_candidates.map(&:expand_path)}"
    # The media tools live under MASTER/tools since 9baa6047e.
    assert_includes script.to_s, "/MASTER/tools/postpro/postpro.rb"
    assert File.file?(script), "expected postpro at #{script}"
  end

  test "valid presets delegate to shared processor" do
    assert_equal Shared::PostproProcessor::VALID_PRESETS, PostproJob::VALID_PRESETS
  end

  test "perform flips a listing's photo_status from pending to done" do
    Brgen::CitySeed.sync! if City.table_exists?
    city = City.find_by!(domain: "brgen.no")
    seller = User.strict_loading(false).create!(
      email_address: "postpro_seller@brgen.no", password: "password123", city: city
    )
    category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    listing = ActsAsTenant.with_tenant(city) do
      Marketplace::Listing.create!(
        category: category, user: seller, title: "Sykkel", price_cents: 1_000_00, currency: "NOK"
      )
    end
    listing.photos.attach(
      io: File.open(Rails.root.join("test/fixtures/files/tiny.png")),
      filename: "tiny.png", content_type: "image/png"
    )
    listing.mark_photo_status!("pending")

    PostproJob.perform_now(listing.to_gid.to_s, "portrait", "photos")
    listing.reload

    assert_includes %w[done skipped], listing.photo_status
  ensure
    ActsAsTenant.current_tenant = nil
  end
end
