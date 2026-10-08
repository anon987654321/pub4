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

  test "sharing a photo into brgen creates a draft with the image attached" do
    Tempfile.create([ "shot", ".png" ]) do |f|
      f.binmode; f.write(PNG); f.rewind
      upload = Rack::Test::UploadedFile.new(f.path, "image/png")
      assert_difference -> { Post.count }, 1 do
        post share_post_path, params: { title: "from my camera roll", media: upload }
      end
      assert_redirected_to edit_post_path(Post.order(:id).last)
      assert Post.order(:id).last.image.attached?, "the shared photo should be attached"
    end
  end
end
