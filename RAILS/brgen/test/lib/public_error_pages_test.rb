# frozen_string_literal: true

require "test_helper"

# brgen's public tree was removed as obsolete and the shared overlay carries only
# 400, 406 and 503, so a deploy left a visitor with Rails' empty default body on
# a 404, a 422 or a 500. These pages are what the live site served before that,
# kept so the address a visitor mistyped answers in words and with a way home.
class PublicErrorPagesTest < ActiveSupport::TestCase
  PAGES = { "404" => "Siden finnes ikke", "422" => "Kunne ikke behandle det", "500" => "Noe gikk galt" }.freeze

  PAGES.each do |code, heading|
    test "public/#{code}.html says what happened, in Norwegian, and links home" do
      html = Rails.root.join("public/#{code}.html").read

      assert_includes html, %(<html lang="nb">)
      assert_includes html, "<h1>#{heading}</h1>"
      assert_includes html, %(href="/")
      assert_includes html, %(rel="icon"), "a page with no icon makes the browser request /favicon.ico and log a 404"
      assert_includes html, %(width=device-width)
    end
  end
end
