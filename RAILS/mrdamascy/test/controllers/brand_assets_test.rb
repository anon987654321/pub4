# frozen_string_literal: true

require "test_helper"

# The brand bar draws public/logo.svg on every page.
class BrandAssetsTest < ActiveSupport::TestCase
  test "the logo stays light and keeps its drawing" do
    logo = Rails.public_path.join("logo.svg").read

    assert_operator logo.bytesize, :<, 25_000, "logo.svg has grown back past 25 KB"
    assert_includes logo, %(viewBox="0 0 3527 971")
    assert_equal 35, logo.scan("<path").size
    assert_no_match(/\d\.\d/, logo[/ d="[^"]*"/], "path data keeps whole viewBox units")
  end
end
