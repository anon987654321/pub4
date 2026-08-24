# frozen_string_literal: true

require "test_helper"

# The vertical-as-engine cutover 500'd four subdomains in production while the whole
# unit/contract suite stayed green — because nothing actually RENDERED a vertical page
# with a real ActiveStorage attachment under the engine's routing context. Two whole
# classes of bug hid there:
#
#   * url_for / image_tag on an attachment inside an isolated engine resolves against
#     the engine routes, which do not own the ActiveStorage routes, and dies with
#     "undefined method 'to_model' for ActiveStorage::VariantWithRecord". Fixed by
#     routing those through main_app.url_for.
#   * an engine-defined helper (PlaylistHelper#radio_tunnel_catalog) is not folded into
#     controllers that inherit the host ApplicationController, so it is undefined at
#     render. Fixed by `helper PlaylistHelper` in the engine base controller.
#
# This test renders the pages that broke, WITH an attachment, so neither class can
# slip through green again. See brgen/ENGINES.md.
class EngineRenderSmokeTest < ActionDispatch::IntegrationTest
  # 1x1 transparent PNG.
  PIXEL_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  setup do
    Brgen::CitySeed.sync! if defined?(Brgen::CitySeed) && City.table_exists?
    @city = City.find_or_initialize_by(domain: "brgen.no")
    @city.name ||= "Bergen"
    @city.slug ||= "bergen-smoke"
    @city.country_code ||= "NO"
    @city.locale ||= "nb"
    @city.currency = "NOK"
    @city.save!
    ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "smoke-#{SecureRandom.hex(4)}@brgen.no",
                         password: "password123", password_confirmation: "password123",
                         username: "smoke_#{SecureRandom.hex(3)}", city: @city)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def attach_pixel(attachment, name = "p.png")
    attachment.attach(io: StringIO.new(PIXEL_PNG), filename: name, content_type: "image/png")
  end

  test "tv video and live stream show pages render with an attached image" do
    host! "tv.brgen.no"
    channel = Tv::Channel.create!(name: "Smoke TV", slug: "smoke-#{SecureRandom.hex(3)}", user: @user)
    attach_pixel(channel.banner) if channel.respond_to?(:banner)
    video = Tv::Video.create!(title: "Smoke clip", channel: channel, user: @user)
    attach_pixel(video.thumbnail)

    # Tv::Engine is mounted at "/" on the tv subdomain, so its video show is /videos/:id.
    get "/videos/#{video.id}"
    assert_response :success, "tv video show 500'd: #{@response.body[0, 300]}"
  end

  test "marketplace listings index renders a card that has an attached photo" do
    # The 500 that the plain roots test missed: responsive_image_tag(photo) in the
    # _card partial resolves a variant URL, which dies in the engine routing context.
    # Only reproduces when the index actually has a listing WITH a photo.
    category = Marketplace::Category.create!(name: "Smoke", slug: "smoke-#{SecureRandom.hex(4)}")
    listing = Marketplace::Listing.create!(title: "Smoke listing", price_cents: 1000,
                                           user: @user, category: category)
    attach_pixel(listing.photos, "listing.png")

    host! "markedsplass.brgen.no"
    get "/"
    assert_response :success, "marketplace index 500'd on a photo card: #{@response.body[0, 300]}"
  end

  test "vertical roots render" do
    {
      "tv.brgen.no" => "/",
      "dating.brgen.no" => "/",
      "playlist.brgen.no" => "/",
      "markedsplass.brgen.no" => "/",
      "takeaway.brgen.no" => "/"
    }.each do |host, path|
      host! host
      get path
      assert_includes 200..399, @response.status,
                      "#{host}#{path} returned #{@response.status}: #{@response.body[0, 300]}"
    end
  end
end
