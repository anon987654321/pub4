# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../lib/operator/namespace_ratchet"

class TestNamespaceRatchet < Minitest::Test
  TOOL = File.expand_path("../tools/namespace_ratchet.rb", __dir__)

  def test_tool_entrypoint_delegates_to_the_live_ratchet
    assert_path_exists TOOL

    out, err, status = Open3.capture3(RbConfig.ruby, TOOL, "--json")

    assert status.success?, "namespace ratchet failed: #{out}#{err}"
    payload = JSON.parse(out)
    assert_kind_of Hash, payload
    assert payload.key?("recorded")
    assert payload.key?("actual")
    refute_empty payload.fetch("recorded")
    assert_equal payload.fetch("recorded").keys.sort, payload.fetch("actual").keys.sort
  end

  # In an export under /private/tmp the skip matched every absolute path, so
  # each directory counted 0 flat files and the ratchet could never rise.
  def test_a_checkout_under_tmp_is_counted_and_its_own_tmp_is_not
    Dir.mktmpdir("namespace-ratchet") do |dir|
      root = File.join(dir, "tmp", "export")

      {
        "flat.rb" => "def helper = 1\n", "named.rb" => "module Tool\nend\n",
        "tmp/scratch.rb" => "def scratch = 1\n", "vendor/gem.rb" => "def gem_helper = 1\n"
      }.each do |rel, body|
        path = File.join(root, "STUDIO", "tool", rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, body)
      end

      flat = Operator::NamespaceRatchet.flat_files("STUDIO/tool", root:).map { |path| File.basename(path) }

      assert_equal ["flat.rb"], flat
    end
  end
end
