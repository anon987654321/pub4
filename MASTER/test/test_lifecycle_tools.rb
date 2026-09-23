# frozen_string_literal: true

require "minitest/autorun"

class LifecycleToolsSpec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # repo_inventory reports anything at the repo root that is not on one of its
  # two allowlists, so a stale list is wrong in both directions at once: it
  # excuses what is gone and reports what belongs. Both had gone stale — five of
  # seven files and four of six directories named subjects that do not exist,
  # while MASTER, RAILS, OPENBSD and STUDIO were reported as non-canonical
  # top-level directories. Held against the tree rather than a fixture, because
  # the tree is what the tool reads.
  def test_the_root_allowlists_name_the_repo_root_exactly
    load_inventory
    repo = File.expand_path("..", ROOT)
    # The tool own reading rather than a second one beside it: root_entries
    # drops what git ignores, and a spec that re-derived the list from
    # Dir.children failed on .DS_Store and the gate ledger while the tool was
    # right.
    present = root_entries
    files, dirs = present.partition { |name| File.file?(File.join(repo, name)) }

    assert_equal files.sort, Object.const_get(:ALLOWED_ROOT_FILES).sort,
                 "repo_inventory's ALLOWED_ROOT_FILES and the repo root have drifted"
    assert_equal dirs.sort, Object.const_get(:ALLOWED_ROOT_DIRS).sort,
                 "repo_inventory's ALLOWED_ROOT_DIRS and the repo root have drifted"
  end

  private

  # The tool is a script with top-level constants and a `$PROGRAM_NAME` guard, so
  # loading it defines them here and runs nothing.
  def load_inventory
    load File.join(ROOT, "tools", "repo_inventory.rb")
  end
end
