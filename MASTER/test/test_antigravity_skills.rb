# frozen_string_literal: true

require_relative "test_helper"

# lib/ground/antigravity/ was ten files and 962 lines with no test, and nine of
# its subsystems had no caller. What survives is the one path Cli::Skills takes:
# Discovery finds the workspace roots, JsonConfig resolves what skills.json
# declares, Skills reads a SKILL.md out of each. The three are pinned here so
# the collapse cannot quietly take the reached half with it.
class TestAntigravitySkills < Minitest::Test
  A = Master::Ground::Antigravity

  def with_workspace
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".git"))
      yield root
    end
  end

  def write_skill(dir, name, description: "does a thing", body: "steps")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"),
               "---\nname: #{name}\ndescription: #{description}\n---\n#{body}\n")
    dir
  end

  # --- Discovery -----------------------------------------------------------

  def test_discovery_finds_every_workspace_root_dir_name
    with_workspace do |root|
      A::Discovery::WORKSPACE_ROOT_DIRS.each { |name| FileUtils.mkdir_p(File.join(root, name)) }
      roots = A::Discovery.new(cwd: root, workspace_root: root).workspace_customization_roots

      assert_equal A::Discovery::WORKSPACE_ROOT_DIRS.size, roots.size
    end
  end

  # A directory that is not one of the four is not a customization root, which
  # is the half that stops every dotfile in a repo from being scanned.
  def test_discovery_ignores_an_unrelated_dotdir
    with_workspace do |root|
      FileUtils.mkdir_p(File.join(root, ".github"))

      assert_empty A::Discovery.new(cwd: root, workspace_root: root).workspace_customization_roots
    end
  end

  def test_discovery_walks_up_to_the_workspace_root_but_no_further
    with_workspace do |root|
      FileUtils.mkdir_p(File.join(root, ".agents"))
      nested = File.join(root, "a", "b")
      FileUtils.mkdir_p(File.join(nested, ".agents"))
      roots = A::Discovery.new(cwd: nested, workspace_root: root).workspace_customization_roots

      assert_equal [File.join(nested, ".agents"), File.join(root, ".agents")], roots
    end
  end

  # --- JsonConfig ----------------------------------------------------------

  def test_json_config_resolves_local_entries_relative_to_the_workspace
    with_workspace do |root|
      cfg = File.join(root, "skills.json")
      File.write(cfg, JSON.generate({ "entries" => [{ "path" => "pack/one" }] }))
      entries = A::JsonConfig.load(cfg, workspace_root: root)

      assert_equal [File.join(root, "pack", "one")], entries.map { |e| e[:path] }
    end
  end

  # Inherited first, local second: the caller keeps the last of a duplicate
  # name, so this order is what makes a local entry win.
  def test_json_config_puts_inherited_entries_before_local_ones
    with_workspace do |root|
      File.write(File.join(root, "base.json"), JSON.generate({ "entries" => [{ "path" => "from_base" }] }))
      cfg = File.join(root, "skills.json")
      File.write(cfg, JSON.generate({ "inherits" => [{ "path" => "base.json" }],
                                      "entries" => [{ "path" => "from_local" }] }))
      paths = A::JsonConfig.load(cfg, workspace_root: root).map { |e| File.basename(e[:path]) }

      assert_equal %w[from_base from_local], paths
    end
  end

  def test_json_config_filters_inherited_entries_by_include_only_and_exclude
    with_workspace do |root|
      File.write(File.join(root, "base.json"),
                 JSON.generate({ "entries" => [{ "path" => "keep_me" }, { "path" => "keep_too" },
                                               { "path" => "drop_me" }] }))
      cfg = File.join(root, "skills.json")
      File.write(cfg, JSON.generate({ "inherits" => [{ "path" => "base.json",
                                                       "include_only" => ["^keep"],
                                                       "exclude" => ["too$"] }] }))
      paths = A::JsonConfig.load(cfg, workspace_root: root).map { |e| File.basename(e[:path]) }

      assert_equal %w[keep_me], paths
    end
  end

  # The filters apply to what is inherited, never to what the file declares
  # itself: a config always gets its own entries.
  def test_json_config_does_not_filter_a_files_own_entries
    with_workspace do |root|
      cfg = File.join(root, "skills.json")
      File.write(cfg, JSON.generate({ "include_only" => ["^nothing"],
                                      "entries" => [{ "path" => "mine" }] }))

      assert_equal %w[mine], A::JsonConfig.load(cfg, workspace_root: root).map { |e| File.basename(e[:path]) }
    end
  end

  def test_json_config_stops_on_an_inherits_cycle
    with_workspace do |root|
      a = File.join(root, "a.json")
      b = File.join(root, "b.json")
      File.write(a, JSON.generate({ "inherits" => [{ "path" => "b.json" }], "entries" => [{ "path" => "from_a" }] }))
      File.write(b, JSON.generate({ "inherits" => [{ "path" => "a.json" }], "entries" => [{ "path" => "from_b" }] }))

      paths = Timeout.timeout(5) { A::JsonConfig.load(a, workspace_root: root) }.map { |e| File.basename(e[:path]) }

      assert_equal %w[from_b from_a], paths
    end
  end

  def test_json_config_reads_absolute_and_tilde_paths_as_written
    config = A::JsonConfig.new("/nowhere/skills.json", workspace_root: "/ws")

    assert_equal "/already/absolute", config.resolve_path("/already/absolute")
    assert_equal File.expand_path("~/global"), config.resolve_path("~/global")
  end

  def test_json_config_returns_nothing_for_unparseable_json
    with_workspace do |root|
      cfg = File.join(root, "skills.json")
      File.write(cfg, "{ not json")

      assert_empty A::JsonConfig.load(cfg, workspace_root: root)
    end
  end

  # --- Skills --------------------------------------------------------------

  # Discovery reads ~/.gemini for the global and built-in roots, so on a machine
  # with the Antigravity CLI installed its five shipped skills land in every
  # assertion below. Only the workspace half is under test here.
  class WorkspaceOnly < A::Discovery
    def global_customization_root = nil
    def builtin_customization_root = nil
  end

  def skills_for(root)
    discovery = WorkspaceOnly.new(cwd: root, workspace_root: root)
    A::Skills.new(discovery:, usage_file: File.join(root, "usage.yml"))
  end

  def test_skills_reads_name_description_and_body_out_of_the_frontmatter
    with_workspace do |root|
      write_skill(File.join(root, ".agents", "skills", "greet"), "greet",
                  description: "says hello", body: "wave")
      found = skills_for(root).discover!

      assert_equal %w[greet], found.map { |s| s[:name] }
      assert_equal "says hello", found.first[:description]
      assert_equal "wave", found.first[:body].strip
      assert_equal :workspace, found.first[:source]
    end
  end

  # A directory with no SKILL.md is not a skill, and neither is one whose
  # frontmatter names nothing — the caller keys on :name and would register an
  # anonymous entry that no /skill invocation can ever reach.
  def test_skills_skips_a_directory_with_no_skill_file_and_a_nameless_one
    with_workspace do |root|
      base = File.join(root, ".agents", "skills")
      FileUtils.mkdir_p(File.join(base, "empty_dir"))
      FileUtils.mkdir_p(File.join(base, "nameless"))
      File.write(File.join(base, "nameless", "SKILL.md"), "---\ndescription: no name\n---\nbody\n")
      write_skill(File.join(base, "real"), "real")

      assert_equal %w[real], skills_for(root).discover!.map { |s| s[:name] }
    end
  end

  def test_skills_lets_a_declared_entry_be_narrowed_by_include_only
    with_workspace do |root|
      pack = File.join(root, "pack")
      write_skill(File.join(pack, "wanted"), "wanted")
      write_skill(File.join(pack, "unwanted"), "unwanted")
      FileUtils.mkdir_p(File.join(root, ".agents"))
      File.write(File.join(root, ".agents", "skills.json"),
                 JSON.generate({ "entries" => [{ "path" => "pack", "include_only" => ["^wanted$"] }] }))

      assert_equal %w[wanted], skills_for(root).discover!.map { |s| s[:name] }
    end
  end

  def test_skills_flags_the_optional_resource_subdirectories
    with_workspace do |root|
      dir = write_skill(File.join(root, ".agents", "skills", "rich"), "rich")
      FileUtils.mkdir_p(File.join(dir, "scripts"))
      skill = skills_for(root).discover!.first

      assert skill[:has_scripts]
      refute skill[:has_references]
    end
  end

  def test_skills_reads_a_reference_but_refuses_one_outside_the_skill_dir
    with_workspace do |root|
      dir = write_skill(File.join(root, ".agents", "skills", "ref"), "ref")
      FileUtils.mkdir_p(File.join(dir, "references"))
      File.write(File.join(dir, "references", "note.md"), "the note")
      File.write(File.join(root, "outside.md"), "secret")
      skills = skills_for(root)

      assert_equal "the note", skills.reference_for("ref", "references/note.md")
      assert_nil skills.reference_for("ref", "../../../outside.md")
    end
  end

  # Usage ordering is the only reason record_used exists: a skill used recently
  # sorts above one that was not, and ties fall back to the name.
  def test_skills_sort_most_recently_used_first
    with_workspace do |root|
      base = File.join(root, ".agents", "skills")
      write_skill(File.join(base, "alpha"), "alpha")
      write_skill(File.join(base, "zulu"), "zulu")
      skills = skills_for(root)

      assert_equal %w[alpha zulu], skills.discover!.map { |s| s[:name] }
      skills.record_used("zulu")

      assert_equal %w[zulu alpha], skills_for(root).discover!.map { |s| s[:name] }
    end
  end

  def test_prompt_catalog_is_nil_when_there_are_no_skills
    with_workspace { |root| assert_nil skills_for(root).prompt_catalog }
  end
end
