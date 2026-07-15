# frozen_string_literal: true

require "test_helper"

class AmberScriptTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("amber.sh")

  # amber.sh's own deploy_tracked_app pipeline copies only the app's own
  # source tree into the deploy target (Rails.root is /home/amber/app there),
  # not the sibling @deploy.sh/@bundle.sh — those are shell tooling run from
  # the source checkout, never part of the deployed app itself. Rails.root's
  # parent only holds them in a source-tree checkout (local dev, CI); on a
  # deployed target, fall back to the known checkout root.
  def self.shared_rails_root
    local = Rails.root.join("..")
    return local if local.join("_deploy.sh").exist?

    Pathname.new(ENV.fetch("PUB4_RAILS_ROOT", "/home/dev/pub4/RAILS"))
  end

  test "deploy script is configured for amber instead of a template placeholder" do
    content = SCRIPT.read

    assert_includes content, "APP_NAME=amber"
    refute_includes content, "%APP_NAME%"
    assert_includes content, "APP_DOMAIN=amber.brgen.no"
  end

  test "deploy script avoids self-copying an amber bundle cache" do
    content = SCRIPT.read
    shared = self.class.shared_rails_root.join("_deploy.sh").read

    assert_includes content, "SHARED_BUNDLE_CACHE"
    assert_includes shared, "${bundle_home} != /home/amber/.bundle"
  end

  test "deploy script delegates to the shared deploy_tracked_app pipeline" do
    content = SCRIPT.read
    shared = self.class.shared_rails_root.join("_deploy.sh").read
    shared << self.class.shared_rails_root.join("_bundle.sh").read

    assert_includes content, 'deploy_tracked_app "$APP_NAME"'
    assert_includes shared, 'bundle_install_as_app "$APP_NAME" "$APP_DIR"'
    assert_includes shared, "bundle config set --local deployment true"
    assert_includes shared, "bundle config set --local without"
    assert_includes shared, "development test"
    refute_includes content, "bundle install --deployment --without"
  end
end
