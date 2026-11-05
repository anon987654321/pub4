# frozen_string_literal: true

require "test_helper"

# A gallery post could not be changed once posted: posts#edit offered only the
# single image field. The edit form now adds, removes and orders its photos,
# and the order is kept (Post::Gallery).
class PostGalleryEditTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @author = User.strict_loading(false).create!(email_address: "gallery-#{SecureRandom.hex(4)}@brgen.no",
                                                 password: "password12345", city: @city, guest: false)
    @post = Post.create!(user: @author, title: "Galleri", content: "tre bilder", city: @city)
    @post.images.attach(Array.new(3) { |n| photo("bilde-#{n}.png") })
    @first, @second, @third = @post.images_attachments.order(:id).to_a

    host! "brgen.no"
    post session_path, params: { email_address: @author.email_address, password: "password12345" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def photo(name) = { io: file_fixture("tiny.png").open, filename: name, content_type: "image/png" }

  # The gallery as the post page orders it, by file name.
  def gallery_names
    ordered = Post.with_attached_images.find(@post.id).ordered_images
    ordered.each_with_object([]) { |image, names| names << image.filename.to_s }
  end

  test "the edit form lists the gallery with a place and a remove box for each photo" do
    get edit_post_path(@post)

    assert_response :success
    assert_select "fieldset.post-gallery-editor ol li", 3
    assert_select "input[name='post[image_positions][#{@second.id}]'][value='2']"
    assert_select "input[type=checkbox][name='post[remove_image_ids][]'][value='#{@third.id}']"
    assert_select "input[type=file][name='post[images][]'][multiple]"
  end

  test "an author reorders, removes and adds photos, and the order is kept" do
    positions = { @first.id => "3", @second.id => "1", @third.id => "2" }
    upload = fixture_file_upload("tiny.png", "image/png")
    form = { title: "Galleri", image_positions: positions, remove_image_ids: [ @third.id.to_s ], images: [ upload ] }
    patch post_path(@post), params: { post: form }

    assert_redirected_to post_path(@post)
    assert_equal %w[bilde-1.png bilde-0.png tiny.png], gallery_names

    get post_path(@post)
    shown = css_select(".post-images img").map { _1["alt"] }
    assert_equal 3, shown.size
  end

  test "a photo from another post cannot be removed through this one" do
    other = Post.create!(user: @author, title: "Annet", content: "x", city: @city)
    other.images.attach(photo("annet.png"))

    foreign = other.images_attachment_ids.first
    patch post_path(@post), params: { post: { title: "Galleri", remove_image_ids: [ foreign ] } }

    elsewhere = other.reload.images
    assert elsewhere.attached?
    kept = @post.reload.images
    assert_equal 3, kept.size
  end
end
