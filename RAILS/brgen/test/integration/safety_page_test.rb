# frozen_string_literal: true

require "test_helper"

# The safety page is public like the legal pages: no account, linked from the
# footer, and it carries the numbers someone in trouble needs.
class SafetyPageTest < ActionDispatch::IntegrationTest
  test "anyone can read it, with the emergency numbers and the police contact" do
    host! "brgen.no"
    get "/safety"

    assert_response :success
    assert_select "article.legal-prose h1", I18n.t("legal.safety_page.heading", locale: :nb)
    assert_includes response.body, "113"
    assert_includes response.body, "116 123"
    assert_select "a[href='https://www.politiet.no/kontakt-politiet/']"
  end

  # A phone in a hand in trouble should dial, not ask the reader to copy digits.
  test "the emergency and helpline numbers are tel: links in both languages" do
    %w[brgen.no lsangeles.com].each do |host|
      host! host
      get "/safety"

      assert_select "a[href='tel:113']", text: "113"
      assert_select "a[href='tel:116123']", text: "116 123"
    end
  end

  # lsangeles.com is the English flagship; brgen.no is always Norwegian.
  test "it reads in English on an English city" do
    host! "lsangeles.com"
    get "/safety"

    assert_response :success
    assert_includes response.body, I18n.t("legal.safety_page.health.helpline_html", locale: :en).split(":").first
  end

  test "the footer links to it" do
    host! "brgen.no"
    get "/privacy"

    assert_select "footer.site-legal a[href='/safety']"
  end
end
