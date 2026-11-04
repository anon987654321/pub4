# frozen_string_literal: true

require "test_helper"

# The demo wardrobe is amber's one public catalogue and the sitemap left it
# out, along with the public feed it links from.
class SitemapTest < ActionDispatch::IntegrationTest

  setup do
    @demo = member(Amber::DemoWardrobe::DEMO_EMAIL)
    @garment = @demo.items.create!(title: "Ivory silk slip dress", category: "Dresses")
    owner = member("creator-#{SecureRandom.hex(4)}@example.test")
    @public_profile = owner.create_creator_profile!(handle: "pub#{SecureRandom.hex(3)}", display_name: "Shown",
                                                    public: true)
    hidden = member("hidden-#{SecureRandom.hex(4)}@example.test")
    @hidden_profile = hidden.create_creator_profile!(handle: "hid#{SecureRandom.hex(3)}", display_name: "Hidden")
    @post = Post.create!(user: owner, body: "Ny jakke")
  end

  # The demo account may already be seeded in the test database.
  def member(email)
    users = User.strict_loading(false)
    users.find_by(email_address: email) || users.create!(email_address: email, password: "password")
  end

  def locations
    get sitemap_path(format: :xml)
    assert_response :success
    Nokogiri::XML(response.body).remove_namespaces!.xpath("//url/loc").map(&:text)
  end

  test "the sitemap lists the demo wardrobe, its garments and the public feed" do
    listed = locations

    assert_includes listed, demo_wardrobe_url
    assert_includes listed, demo_wardrobe_item_url(@garment)
    assert_includes listed, posts_url
    assert_includes listed, post_url(@post)
  end

  test "the sitemap lists public creator profiles and no hidden ones" do
    listed = locations

    assert_includes listed, creator_profile_url(@public_profile.handle)
    assert_not_includes listed, creator_profile_url(@hidden_profile.handle)
  end
end
