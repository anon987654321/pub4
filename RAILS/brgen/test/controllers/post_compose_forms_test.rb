# frozen_string_literal: true

require "test_helper"

# posts#new and posts#edit: what the forms offer, what they say, and where the
# author lands after saving or deleting.
class PostComposeFormsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city

    @author = User.strict_loading(false).create!(email_address: "compose-#{SecureRandom.hex(4)}@brgen.no",
                                                 password: "password12345", city: @city, guest: false)
    owner = User.strict_loading(false).create!(email_address: "club-#{SecureRandom.hex(4)}@brgen.no",
                                               password: "password12345", city: @city, guest: false)
    @closed = Community.create!(user: owner, name: "Lukket #{SecureRandom.hex(3)}", privacy: "private")
    @open = Community.create!(user: owner, name: "Åpen #{SecureRandom.hex(3)}", privacy: "public")
    @neighborhood = Neighborhood.create!(city: @city, name: "Nordnes #{SecureRandom.hex(2)}",
                                         slug: "nordnes-#{SecureRandom.hex(3)}")
    @post = Post.create!(user: @author, title: "Min tekst", content: "hei", city: @city)

    host! "brgen.no"
    post session_path, params: { email_address: @author.email_address, password: "password12345" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def page = Nokogiri::HTML(response.body)

  def community_options
    page.css("select[name='post[community_id]'] option").map(&:text)
  end

  def content_limit
    Post.validators_on(:content).grep(ActiveModel::Validations::LengthValidator).first.options[:maximum]
  end

  test "a fresh form offers the neighbourhood field" do
    get new_post_path

    assert_select "select[name='post[neighborhood_id]'] option", text: @neighborhood.name
  end

  test "the new form offers only communities the writer may post in" do
    get new_post_path

    assert_includes community_options, @open.name
    refute_includes community_options, @closed.name
  end

  test "the edit form offers only communities the writer may post in" do
    get edit_post_path(@post)

    assert_includes community_options, @open.name
    refute_includes community_options, @closed.name
  end

  test "the title fields carry a translated label and no playlist placeholder" do
    [ new_post_path, edit_post_path(@post) ].each do |path|
      get path

      field = page.at_css("input[name='post[title]']")
      assert_equal I18n.t("posts.title_label"), page.at_css("label[for='#{field['id']}']").text.strip, path
      refute_equal I18n.t("playlist.title"), field["placeholder"], path
    end
  end

  test "the body allows what Post validates" do
    [ new_post_path, edit_post_path(@post) ].each do |path|
      get path

      assert_equal content_limit.to_s, page.at_css("textarea[name='post[content]']")["maxlength"], path
    end
  end

  test "saving an edit says so" do
    patch post_path(@post), params: { post: { title: "Ny tittel" } }

    assert_redirected_to post_path(@post.reload)
    assert_equal I18n.t("flash.post_updated"), flash[:notice]
  end

  test "deleting from a list returns there with a notice" do
    delete post_path(@post), headers: { "HTTP_REFERER" => "http://brgen.no/bookmarks" }

    assert_redirected_to "/bookmarks"
    assert_equal I18n.t("flash.post_deleted"), flash[:notice]
  end

  test "deleting from the post's own page lands on the post list" do
    delete post_path(@post), headers: { "HTTP_REFERER" => "http://brgen.no#{post_path(@post)}" }

    assert_redirected_to posts_path
  end

  # The toolbar buttons bound mousedown only, so Enter and Space (which fire
  # click) did nothing, and a title plus a B or i glyph named them.
  test "the formatting buttons work from the keyboard and say their state" do
    get new_post_path

    buttons = page.css(".tiptap_toolbar button")
    assert_equal 3, buttons.size
    buttons.each do |button|
      assert_match(/click->tiptap-editor#/, button["data-action"])
      assert_equal "false", button["aria-pressed"]
      assert button["aria-label"].present?
      assert_nil button["title"]
    end
    assert_equal I18n.t("compose.bold"), buttons.first["aria-label"]
  end
end
