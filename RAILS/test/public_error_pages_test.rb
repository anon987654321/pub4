# frozen_string_literal: true

require "minitest/autorun"

# allow_browser answers an old browser by rendering public/406-unsupported-browser.html.
# With the file missing, that answer was itself an ArgumentError, so the visitor got a 500.
class PublicErrorPagesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  %w[brgen amber bsdports].each do |app|
    define_method("test_#{app}_has_every_page_rails_renders_for_a_status") do
      %w[404 406-unsupported-browser 422 500].each do |name|
        assert File.file?(File.join(ROOT, app, "public", "#{name}.html")), "#{app}/public/#{name}.html is missing"
      end
    end
  end
end
