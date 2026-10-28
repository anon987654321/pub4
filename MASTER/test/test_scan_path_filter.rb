# frozen_string_literal: true

require_relative "test_helper"

# `/scan face` resolves to RAILS/master/public (CLI::Scan::Request::TARGET_ALIASES). The
# generated face bundles sit there, and a scan rooted at that directory must
# skip them exactly as a scan rooted at MASTER or the repo does.
class TestScanPathFilter < Minitest::Test
  Scanner = Master::Fix::Scanner
  PUBLIC = File.join(Master::RAILS_ROOT, "master", "public")

  def test_the_face_alias_points_at_the_face_sources
    assert_equal PUBLIC, Master::CLI::Scan::Request::TARGET_ALIASES.fetch("face")
  end

  def test_generated_bundles_are_skipped_from_every_root
    Master::Fix::Scan::PathFilter::GENERATED_FACE_BUNDLES.each do |bundle|
      path = File.join(Master::REPO_ROOT, bundle)
      [PUBLIC, File.join(Master::REPO_ROOT, "RAILS", "master"), Master::ROOT, Master::REPO_ROOT].each do |root|
        assert Scanner.skip_path?(path, root:), "#{bundle} is scanned from #{root}"
      end
    end
  end

  def test_compiled_assets_are_skipped_from_the_face_root
    assert Scanner.skip_path?(File.join(PUBLIC, "assets", "face-abc123.js"), root: PUBLIC)
  end

  def test_an_authored_face_source_is_still_scanned
    refute Scanner.skip_path?(File.join(PUBLIC, "visual_bridge.js"), root: PUBLIC)
    refute Scanner.skip_path?(File.join(PUBLIC, "visual_bridge.js"), root: Master::ROOT)
  end

  # EXEMPTIONS_EXPIRE: an exemption outliving its subject excuses whatever next
  # takes the name. Each entry must reach a tracked file, or be build output a
  # .gitignore rule already names.
  def test_every_path_exemption_names_something_that_exists
    tracked = IO.popen(["git", "-C", Master::REPO_ROOT, "ls-files"], &:read).split("\n")
    filter = Master::Fix::Scan::PathFilter
    entries = filter::SKIP_PATH_FRAGMENTS
    stale = entries.reject do |entry|
      tracked.any? { |path| path.start_with?(entry) || path.include?("/#{entry}") } || ignored_output?(entry)
    end
    assert_empty stale, "path exemptions naming nothing in the tree"
  end

  def ignored_output?(entry)
    probe = "RAILS/brgen/#{entry}probe"
    system("git", "-C", Master::REPO_ROOT, "check-ignore", "-q", probe) ||
      system("git", "-C", Master::REPO_ROOT, "check-ignore", "-q", "#{entry}probe")
  end

  def test_a_path_outside_master_is_judged_by_its_own_root
    rails_file = File.join(Master::REPO_ROOT, "RAILS", "brgen", "app", "models", "post.rb")
    refute Scanner.skip_path?(rails_file, root: Master::REPO_ROOT)
  end

  def test_authored_views_named_reports_and_the_committed_claude_settings_are_scanned
    root = Master::REPO_ROOT
    scanned = %w[RAILS/brgen/app/views/admin/reports/index.html.erb .claude/settings.json]

    scanned.each { |relative| refute Scanner.skip_path?(File.join(root, relative), root:), relative }
  end

  def test_generated_reports_and_agent_worktrees_are_still_skipped
    root = Master::REPO_ROOT
    skipped = %w[MASTER/checks/reports/run.json .claude/worktrees/a/MASTER/lib/x.rb]

    skipped.each { |relative| assert Scanner.skip_path?(File.join(root, relative), root:), relative }
  end

  def test_an_extensionless_script_with_a_ruby_magic_comment_is_ruby
    Dir.mktmpdir do |dir|
      script = File.join(dir, "reach")
      File.write(script, "# frozen_string_literal: true\n\nputs 1\n")

      assert_equal "ruby", Master.language_for(script)
    end
  end

  def test_an_extensioned_data_file_with_a_ruby_magic_comment_is_not_ruby
    Dir.mktmpdir do |dir|
      conf = File.join(dir, "unscoped_protocol_pass.conf")
      File.write(conf, "# frozen_string_literal: true\nblock log all\npass in quick on $ext_if proto tcp\n")

      assert_nil Master.language_for(conf)
    end
  end

  # Every tracked file with a language is linted unless a rule says why not, and the rules are all about files
  # nobody authored: vendored code, deliberately bad fixtures, generated bundles and schemas.
  UNAUTHORED = %r{/vendor/|/fixtures/|/public/|db/schema\.rb|service-worker\.js|\.min\.|/db/structure\.sql}

  def test_no_authored_tracked_file_with_a_language_is_skipped_without_a_reason
    root = Master::REPO_ROOT
    tracked = IO.popen(["git", "-C", root, "ls-files", "-z"], &:read).force_encoding("UTF-8").split("\0")
    tracked = tracked.select(&:valid_encoding?)
    unexplained = tracked.select do |relative|
      path = File.join(root, relative)
      File.file?(path) && Master.language_for(path) && Scanner.skip_path?(path, root:) && !relative.match?(UNAUTHORED)
    end

    assert_empty unexplained, "authored files the scan never reads: narrow the rule that skips them"
  end
end
