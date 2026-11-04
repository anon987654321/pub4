# frozen_string_literal: true

require "test_helper"

# The quick composer posts with a nearby toggle. Leaving it off must not cost
# a signed-in author their name.
class PostAttributionTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
    @author = User.create!(email_address: "navngitt-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                           username: "navngitt_#{SecureRandom.hex(3)}")
    post session_path, params: { email_address: @author.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a quick-compose post without nearby stays attributed to its author" do
    assert_difference -> { Post.count }, 1 do
      post posts_path, params: { post: { content: "Fin dag på Bryggen", nearby: "0" } }
    end

    created = Post.order(:id).last
    assert_equal @author.id, created.user_id
    assert_not created.anonymous?
    assert_nil created.latitude
  end
end
