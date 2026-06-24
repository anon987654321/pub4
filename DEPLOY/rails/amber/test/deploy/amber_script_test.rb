# frozen_string_literal: true

require "test_helper"

class AmberScriptTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("amber.sh")

  test "deploy script is configured for amber instead of a template placeholder" do
    content = SCRIPT.read

    assert_includes content, "APP_NAME=amber"
    refute_includes content, "%APP_NAME%"
    assert_includes content, "APP_DOMAIN=amber.brgen.no"
  end

  test "deploy script avoids self-copying an amber bundle cache" do
    content = SCRIPT.read

    assert_includes content, "SHARED_BUNDLE_CACHE"
    assert_includes content, "${bundle_home} != /home/amber/.bundle"
  end

  test "deploy script uses modern bundler deployment configuration" do
    content = SCRIPT.read

    assert_includes content, "bundle config set --local deployment true"
    assert_match(/bundle config set --local without ["']development test["']/, content)
    refute_includes content, "bundle install --deployment --without"
  end
end
