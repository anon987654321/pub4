# frozen_string_literal: true

require_relative "test_helper"
require "master"

# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/face_manifest_helper"

class MasterNamespaceSpec < Minitest::Test
  include FaceManifestHelper

  def read(path)
    File.read(File.join(Master::ROOT, path))
  end

  def test_master_namespace_exposes_canonical_facade
    source = read("web/public/master_namespace.js")

    %w[boot face speech speechRuntime speechPlayback events ecology chat container attention].each do |name|
      assert_includes source, %("#{name}")
    end
    assert_includes source, "Object.defineProperty"
    assert_includes source, "window.MASTER = root"
  end

  def test_chat_index_loads_master_namespace_in_deferred_manifest
    assert_includes shell_manifest, "master_namespace"
  end
end

# frozen_string_literal: true
class TestSmokeChatProbe < Minitest::Test
  def test_smoke_chat_bypasses_container_warmup
    app = File.read(File.join(Master::ROOT, "web", "app", "controllers", "application_controller.rb"))
    chat = File.read(File.join(Master::ROOT, "web", "app", "controllers", "chat_controller.rb"))
    assert_includes app, "smoke_chat_probe?"
    assert_includes chat, "stream_smoke_reply"
    assert_includes chat, "ping"
  end
end

# frozen_string_literal: true
class TestPropshaftPaths < Minitest::Test
  def test_excludes_digest_output_directory
    app_rb = File.read(File.join(Master::ROOT, "web", "config", "application.rb"))
    safety = File.read(File.join(Master::ROOT, "web", "config", "initializers", "propshaft_safety.rb"))
    assert_includes app_rb, "excluded_paths"
    assert_includes app_rb, "public", "assets"
    assert_includes safety, '"assets", "assets"'
  end

  def test_deploy_rc_cleans_nested_assets
    rc = File.read(File.join(Master::ROOT, "..", "OPENBSD", "etc", "rc.d", "master"))
    assert_includes rc, "public/assets/assets"
    assert_includes rc, "assets:precompile"
  end
end
