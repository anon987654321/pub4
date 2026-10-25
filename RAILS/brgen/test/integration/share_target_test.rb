# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "base64"

class ShareTargetTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = ActsAsTenant.with_tenant(@city) do
      Community.create!(name: "General #{SecureRandom.hex(3)}") unless Community.exists?
      User.create!(email_address: "share-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "sh_#{SecureRandom.hex(3)}", city: @city)
    end
    host! "brgen.no"
    post session_path, params: { email_address: @user.email_address, password: "password12345" }
  end

  test "sharing a photo stages a private draft and does not create a post" do
    Tempfile.create([ "shot", ".png" ]) do |file|
      file.binmode
      file.write(PNG)
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "image/png")
      assert_no_difference -> { Post.count } do
        assert_difference -> { ShareDraft.count }, 1 do
          post share_post_path, params: { title: "from my camera roll", media: upload }
        end
      end
      draft = ShareDraft.order(:id).last
      assert_redirected_to share_draft_path(draft)
      assert_equal @user.id, draft.user_id
      assert_equal @city.id, draft.city_id
      assert draft.images.attached?, "the shared photo should be staged"
      refute draft.video.attached?
    end
  end

  test "a shared video remains private until publication" do
    Tempfile.create([ "clip", ".mp4" ]) do |file|
      file.binmode
      file.write("video")
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "video/mp4")
      assert_no_difference -> { Post.count } do
        post share_post_path, params: { title: "A shared clip", media: upload }
      end
      draft = ShareDraft.order(:id).last
      assert_redirected_to share_draft_path(draft)
      assert draft.video.attached?
      refute draft.images.attached?
    end
  end

  test "explicit publication transfers staged media and destroys the private draft" do
    draft = ShareDraft.create!(
      user: @user, city: @city, title: "Ready to publish", content: "A neighbourly update",
      expires_at: 24.hours.from_now
    )
    draft.images.attach(io: StringIO.new(PNG), filename: "shared.png", content_type: "image/png")

    assert_difference -> { Post.count }, 1 do
      post publish_share_draft_path(draft), params: { post: { title: "Ready to publish", content: "A neighbourly update" } }
    end
    published = Post.order(:id).last
    assert_redirected_to post_path(published)
    assert published.image.attached?
    refute ShareDraft.exists?(draft.id)
  end

  test "an unverified account cannot stage a share" do
    @user.update_column(:email_verified_at, nil)
    Tempfile.create([ "shot", ".png" ]) do |file|
      file.binmode
      file.write(PNG)
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "image/png")
      assert_no_difference -> { ShareDraft.count } do
        assert_no_difference -> { Post.count } do
          post share_post_path, params: { title: "blocked", media: upload }
        end
      end
      assert_response :redirect
    end
  end

  test "a community from another city cannot be selected at publication" do
    draft = ShareDraft.create!(
      user: @user, city: @city, title: "City scoped", content: "Only this city",
      expires_at: 24.hours.from_now
    )
    other_city = City.create!(
      name: "Other city", slug: "other-#{SecureRandom.hex(3)}",
      domain: "other-#{SecureRandom.hex(3)}.example", country_code: "NO", locale: "nb", currency: "NOK"
    )
    other_community = ActsAsTenant.with_tenant(other_city) do
      Community.create!(name: "Foreign #{SecureRandom.hex(3)}", city: other_city)
    end

    assert_no_difference -> { Post.count } do
      post publish_share_draft_path(draft), params: {
        post: { title: "City scoped", content: "Only this city", community_id: other_community.id }
      }
    end
    assert_redirected_to share_draft_path(draft)
    assert ShareDraft.exists?(draft.id), "a rejected publish attempt must preserve the private draft"
  end

  test "a different member cannot open another member's share draft" do
    draft = ShareDraft.create!(
      user: @user, city: @city, title: "Private", content: "",
      expires_at: 24.hours.from_now
    )
    other = User.create!(
      email_address: "other-share-#{SecureRandom.hex(4)}@brgen.no",
      password: "password12345", username: "other_#{SecureRandom.hex(3)}", city: @city
    )
    post session_path, params: { email_address: other.email_address, password: "password12345" }

    get share_draft_path(draft)
    assert_response :not_found
  end
end
