# frozen_string_literal: true

require "minitest/autorun"

class LifecycleToolsSpec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # repo_inventory reports anything at the repo root that is not on one of its
  # two allowlists, so a stale list is wrong in both directions at once: it
  # excuses what is gone and reports what belongs. Held against the tree rather
  # than a fixture, because the tree is what the tool reads.
  def test_the_root_allowlists_name_the_repo_root_exactly
    load_inventory
    repo = File.expand_path("..", ROOT)
    # The tool's own reading rather than a second one beside it: root_entries
    # drops what git ignores, which Dir.children would not.
    present = root_entries
    files, dirs = present.partition { |name| File.file?(File.join(repo, name)) }
    assert_equal files.sort, Object.const_get(:ALLOWED_ROOT_FILES).sort,
                 "repo_inventory's ALLOWED_ROOT_FILES and the repo root have drifted"
    assert_equal dirs.sort, Object.const_get(:ALLOWED_ROOT_DIRS).sort,
                 "repo_inventory's ALLOWED_ROOT_DIRS and the repo root have drifted"
  end

  def test_media_tool_compatibility_links_point_at_studio
    # Each entry names its canonical file: dilla and replicate are one-file
    # entrypoints, and STUDIO/replicate/client.rb is replicate's. lora and
    # postpro retired with their STUDIO trees; a symlink must not outlive the
    # tree it points at. Restoration re-adds the link and this row together.
    homes = { "dilla" => ["dilla", "dilla.rb"], "replicate" => ["replicate", "client.rb"] }
    homes.each do |tool, (home, entry_name)|
      link = File.join(ROOT, "tools", tool)
      target = "../../STUDIO/#{home}"

      assert File.symlink?(link), "MASTER/tools/#{tool} must remain a compatibility symlink"
      assert_equal target, File.readlink(link), "MASTER/tools/#{tool} target drifted"

      entry = File.join(ROOT, "..", "STUDIO", home, entry_name)
      assert File.file?(entry), "missing canonical STUDIO/#{home}/#{entry_name}"
    end
  end

  def test_media_tools_have_one_physical_home
    %w[dilla replicate].each do |tool|
      path = File.join(ROOT, "tools", tool)
      assert File.symlink?(path), "MASTER/tools/#{tool} must not become a second physical tool tree"
    end
  end

  private

  # The tool is a script with top-level constants and a `$PROGRAM_NAME` guard, so
  # loading it defines them here and runs nothing.
  def load_inventory
    load File.join(ROOT, "tools", "repo_inventory.rb")
  end
end
