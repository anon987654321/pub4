# frozen_string_literal: true

require "minitest/autorun"
require_relative "face_manifest_helper"

class MasterNamespaceSpec < Minitest::Test
  include FaceManifestHelper

  ROOT = File.expand_path("../..", __dir__)

  def read(path)
    File.read(File.join(ROOT, path))
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
