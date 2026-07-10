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
    shared = Rails.root.join("../shared/deploy/@shared_functions.sh").read

    assert_includes content, "SHARED_BUNDLE_CACHE"
    assert_includes shared, "${bundle_home} != /home/amber/.bundle"
  end

  test "deploy script delegates to the shared deploy_tracked_app pipeline" do
    content = SCRIPT.read
    shared = Rails.root.join("../shared/deploy/@shared_functions.sh").read

    assert_includes content, 'deploy_tracked_app "$APP_NAME"'
    assert_includes shared, 'bundle_install_as_app "$APP_NAME" "$APP_DIR"'
    assert_includes shared, "bundle config set --local deployment true"
    assert_includes shared, "bundle config set --local without"
    assert_includes shared, "development test"
    refute_includes content, "bundle install --deployment --without"
  end
end
