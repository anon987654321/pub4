# frozen_string_literal: true

require "test_helper"

# nb.yml and en.yml were both complete, nothing read a requested language,
# and nothing linked to the other one.
class LocaleSwitchTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    @port = Port.create!(platform:, category:, name: "git", version: "2", pkgpath: "devel/git")
  end

  test "the footer offers both languages, and the choice sticks" do
    get root_path
    assert_select "html[lang=nb]"
    assert_select ".site-legal nav a[lang=en][href=?]", "/?locale=en"
    assert_select ".site-legal nav a[lang=nb][aria-current=true]"

    get root_path(locale: "en")
    assert_select "html[lang=en]"

    get port_path(@port)
    assert_select "html[lang=en]"
    assert_select ".site-legal nav a[lang=en][aria-current=true]"
  end

  test "Accept-Language is honoured" do
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "en-GB,en;q=0.9" }
    assert_select "html[lang=en]"
  end

  test "a port page's ETag differs by language" do
    get port_path(@port)
    norwegian = response.headers["ETag"]

    get port_path(@port, locale: "en"), headers: { "If-None-Match" => norwegian }
    assert_response :success, "the English page revalidated the Norwegian copy"
  end
end
