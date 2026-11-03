# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "tmpdir"

load File.expand_path("../bin/nokogiri-openbsd", __dir__)

# The tool that builds nokogiri on vm23. On 2026-11-03 its `gem fetch` filled the
# box's swap and stopped every app; it now downloads the one file, checks it, and
# will not start a build on a box short of swap.
class TestNokogiriOpenbsd < Minitest::Test
  Tool = NokogiriOpenbsd

  # Replace one of the tool's functions for the block, then put it back.
  def with(name, value)
    original = Tool.method(name)
    Tool.define_singleton_method(name) { |*args, **kw| value.is_a?(Proc) ? value.call(*args, **kw) : value }
    yield
  ensure
    Tool.define_singleton_method(name, original)
  end

  def test_the_patch_renames_only_the_clashing_hashmap_identifiers
    source = "void *(*__malloc)(size_t); __free(p); __realloc_more(x);"
    assert_equal "void *(*gumbo_hashmap_malloc)(size_t); gumbo_hashmap_free(p); __realloc_more(x);",
                 Tool.patch(source)
  end

  BODY = "gem bytes"
  WRITER = ->(_uri, path, **) { File.binwrite(path, BODY) }

  # The file the tool kept, from a stubbed download, against a published checksum.
  def download_with(sha)
    Dir.mktmpdir do |dir|
      with(:fetch_to, WRITER) { with(:published_sha, sha) { File.basename(Tool.download("1.19.7", dir)) } }
    end
  end

  def test_a_download_whose_checksum_matches_is_kept
    assert_equal "nokogiri-1.19.7.gem", download_with(Digest::SHA256.hexdigest(BODY))
  end

  def test_a_download_whose_checksum_differs_stops_the_tool
    assert_raises(SystemExit) { capture_io { download_with("0" * 64) } }
  end

  def test_the_guard_refuses_a_build_on_a_box_short_of_swap
    with(:free_swap_mb, 120) do
      err = capture_io { assert_raises(SystemExit) { Tool.memory_guard!(force: false) } }.last
      assert_match(/only 120 MB of swap free/, err)
      Tool.memory_guard!(force: true)
    end
    with(:free_swap_mb, 900) { Tool.memory_guard!(force: false) }
    with(:free_swap_mb, nil) { Tool.memory_guard!(force: false) }
  end
end
