# frozen_string_literal: true

require "test_helper"

# The first brgen's community rules (2015), restored: public, linked from the
# footer, every rule rendered, and without the old page's legal clauses.
class RulesPageTest < ActionDispatch::IntegrationTest
  test "anyone can read every rule" do
    host! "brgen.no"
    get "/rules"

    assert_response :success
    assert_select "article.legal-prose h1", I18n.t("legal.rules_page.heading", locale: :nb)
    rule_count = Shared::Rules::RULE_SECTIONS.values.sum(&:size)
    assert_select "article.legal-prose li", rule_count
    assert_includes response.body, I18n.t("legal.rules_page.impersonation.pretending", locale: :nb)
  end

  test "it reads in English on an English city" do
    host! "lsangeles.com"
    get "/rules"

    assert_response :success
    assert_includes response.body, I18n.t("legal.rules_page.forbidden.harm", locale: :en)
  end

  test "the footer links to it" do
    host! "brgen.no"
    get "/privacy"

    assert_select "footer.site-legal a[href='/rules']"
  end
end
