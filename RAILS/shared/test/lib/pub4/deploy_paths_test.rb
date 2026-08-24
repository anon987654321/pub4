# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require_relative "../../../lib/pub4/deploy_paths"

class DeployPathsTest < Minitest::Test
  def test_postpro_resolves_under_studio
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => rails_root) do
      script = Pub4::DeployPaths.postpro_script
      assert script, "expected postpro script"
      assert_includes script.to_s, "/STUDIO/postpro/postpro.rb"
      assert File.file?(script)
    end
  end

  def test_repligen_resolves_under_studio
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => rails_root) do
      script = Pub4::DeployPaths.repligen_script
      assert script, "expected repligen script"
      assert_includes script.to_s, "/STUDIO/repligen/repligen.rb"
      assert File.file?(script)
    end
  end

  def test_dilla_resolves_under_studio
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => rails_root) do
      script = Pub4::DeployPaths.dilla_script
      assert script, "expected dilla script"
      assert_includes script.to_s, "/STUDIO/dilla/dilla.rb"
      assert File.file?(script)
    end
  end

  def test_deploy_root_from_pub4_root
    with_env("PUB4_ROOT" => repo_root, "PUB4_RAILS_ROOT" => nil, "PUB4_DEPLOY_ROOT" => nil) do
      assert_equal File.join(repo_root, "OPENBSD"), Pub4::DeployPaths.deploy_root.to_s
    end
  end

  # Every test above sets PUB4_ROOT and PUB4_RAILS_ROOT, which is why nobody
  # noticed that resolution was broken without them. rails_root fell back to
  # DEFAULT_RAILS (/home/dev/pub4/RAILS — a path that exists only on the VPS), so
  # in any local clone all of these returned nil and `bin/rails test` died at load
  # time on radio_bergen_study_test.rb before running a single test.
  def test_resolves_from_the_checkout_with_no_env_vars
    with_env("PUB4_ROOT" => nil, "PUB4_RAILS_ROOT" => nil, "PUB4_DEPLOY_ROOT" => nil) do
      assert_equal rails_root, Pub4::DeployPaths.rails_root.to_s
      assert_equal repo_root, Pub4::DeployPaths.repo_root.to_s

      %i[postpro_script repligen_script dilla_script radio_bergen_study_script].each do |script|
        resolved = Pub4::DeployPaths.public_send(script)
        assert resolved, "expected #{script} to resolve without PUB4_* env vars"
        assert File.file?(resolved), "#{script} resolved to a non-file: #{resolved}"
        assert resolved.to_s.start_with?(repo_root), "#{script} resolved outside the checkout: #{resolved}"
      end
    end
  end

  # repo_root used to be deploy_root/.., and deploy_root is already rails_root/..,
  # so the derived value sat one level above the checkout.
  def test_repo_root_is_the_checkout_not_its_parent
    with_env("PUB4_ROOT" => nil, "PUB4_RAILS_ROOT" => rails_root, "PUB4_DEPLOY_ROOT" => nil) do
      assert_equal repo_root, Pub4::DeployPaths.repo_root.to_s
      assert_equal File.join(repo_root, "STUDIO/dilla/dilla.rb"),
                   Pub4::DeployPaths.repo_join("STUDIO/dilla/dilla.rb").to_s
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
    old = vars.keys.to_h { |key| [ key, ENV[key] ] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
