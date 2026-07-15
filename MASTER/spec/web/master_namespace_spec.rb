# frozen_string_literal: true

require "minitest/autorun"

class MasterNamespaceSpec < Minitest::Test
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
    index = read("web/app/views/chat/index.html.erb")
    tag_line = index[/javascript_include_tag\(\*%w\[([^\]]+)\]/, 1].to_s

    assert_includes tag_line.split, "master_namespace"
  end
end