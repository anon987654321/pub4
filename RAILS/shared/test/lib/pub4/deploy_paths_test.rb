# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require_relative "../../../lib/pub4/deploy_paths"

class DeployPathsTest < Minitest::Test
  def test_postpro_resolves_under_studio
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => rails_root) do
      script = Pub4::DeployPaths.postpro_script
      assert script, "expected postpro script"
      assert_includes script.to_s, "/studio/postpro/postpro.rb"
      assert File.file?(script)
    end
  end

  def test_repligen_resolves_under_studio
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => rails_root) do
      script = Pub4::DeployPaths.repligen_script
      assert script, "expected repligen script"
      assert_includes script.to_s, "/studio/repligen/repligen.rb"
      assert File.file?(script)
    end
  end

  def test_deploy_root_from_pub4_root
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => nil, "PUB4_DEPLOY_ROOT" => nil) do
      assert_equal File.join(repo_root, "OPENBSD"), Pub4::DeployPaths.deploy_root.to_s
    end
  end

  private

  def repo_root
    @repo_root ||= File.expand_path("../../../../..", __dir__)
  end

  def rails_root
    File.join(repo_root, "RAILS")
  end

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
