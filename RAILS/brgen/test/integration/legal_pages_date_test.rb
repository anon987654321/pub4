# frozen_string_literal: true

require "test_helper"

# The privacy, terms and cookies pages carry one "last updated" date, read
# from PagesController::UPDATED_ON and written out per locale, so the
# Norwegian and English pages cannot name different days. Each page's own
# nav of the other legal pages is labelled, apart from the footer's.
class LegalPagesDateTest < ActionDispatch::IntegrationTest
  ISO = PagesController::UPDATED_ON.iso8601

  test "every legal page dates itself from the one constant, in both languages" do
    { "brgen.no" => /12\. august 2026/, "lsangeles.com" => /August 12, 2026|12 August 2026/ }.each do |host, words|
      host! host
      %w[/privacy /terms /cookies].each do |path|
        get path

        assert_response :success
        assert_select "p.legal-updated time[datetime='#{ISO}']", text: words
      end
    end
  end

  test "the legal pages' own nav has a name of its own" do
    host! "brgen.no"
    %w[/privacy /terms /cookies].each do |path|
      get path

      assert_select "article.legal-prose nav[aria-label=?]", "Andre juridiske sider"
    end
  end
end
