# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../lib/fix/rename_sweep"

class TestFileRename < Minitest::Test
  PARTIAL = "RAILS/shared/app/assets/stylesheets/_zen_thing.scss"
  APP = "RAILS/amber/app/assets/stylesheets/application.scss"
  DOC = "RAILS/docs/notes.md"

  # Rules unchanged by a rename: every stylesheet's text minus its load lines.
  SAME_RULES = lambda do |root|
    Dir[File.join(root, "RAILS/**/*.scss")].sort.to_h do |path|
      [File.basename(File.dirname(path)), File.read(path).lines.grep_v(/@(use|forward|import)/).join]
    end.then { |by_dir| { "amber" => by_dir.values.join } }
  end

  def setup
    @root = Dir.mktmpdir("file-rename")
    write(PARTIAL, ".thing { color: red; }\n")
    write(APP, %(@use "zen_thing";\n.app { margin: 0; }\n))
    write(DOC, "The thing lives in _zen_thing.scss, loaded by amber.\n")
    git("init", "-q")
    git("add", ".")
    git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def teardown = FileUtils.remove_entry(@root)

  def rename(css_rules: SAME_RULES)
    Master::Fix::FileRename.new(repo_root: @root, css_rules:)
  end

  def test_a_proved_rename_moves_the_file_rewrites_its_readers_and_commits
    result = rename.call(PARTIAL, "_thing.scss", reason: "zen_ says nothing")

    assert result.ok?, -> { result.message }
    refute File.exist?(File.join(@root, PARTIAL))
    assert File.exist?(File.join(@root, "RAILS/shared/app/assets/stylesheets/_thing.scss"))
    assert_includes read(APP), %(@use "thing";)
    assert_includes read(DOC), "_thing.scss"
    assert_empty git("status", "--porcelain").strip
    assert_match(/_zen_thing\.scss is _thing\.scss/, git("log", "-1", "--format=%B"))
  end

  def test_a_failed_proof_puts_everything_back
    calls = 0
    changing = ->(_root) { calls += 1; { "amber" => "build #{calls}" } }
    result = rename(css_rules: changing).call(PARTIAL, "_thing.scss", reason: "test")

    refute result.ok?
    assert_match(/compiled CSS changed for amber/, result.message)
    assert File.exist?(File.join(@root, PARTIAL))
    refute File.exist?(File.join(@root, "RAILS/shared/app/assets/stylesheets/_thing.scss"))
    assert_includes read(APP), %(@use "zen_thing";)
    assert_empty git("status", "--porcelain").strip
  end

  def test_a_reader_with_uncommitted_work_is_left_alone
    File.write(File.join(@root, APP), "#{read(APP)}.extra { top: 0; }\n")
    result = rename.call(PARTIAL, "_thing.scss", reason: "test")

    refute result.ok?
    assert_equal :policy, result.category
    assert File.exist?(File.join(@root, PARTIAL))
  end

  def test_only_kinds_with_a_proof_are_renamed
    write("MASTER/lib/thing.rb", "module Thing; end\n")
    assert_nil Master::Fix::FileRename.kind(File.join(@root, "MASTER/lib/thing.rb"))
    assert_nil Master::Fix::FileRename.kind(File.join(@root, "RAILS/README.md"))
    assert_equal :stylesheet, Master::Fix::FileRename.kind(File.join(@root, PARTIAL))
    assert_equal :document, Master::Fix::FileRename.kind(File.join(@root, DOC))
  end

  def test_a_name_must_keep_its_kind_and_not_collide
    review = Master::Fix::NameReview.new(agent: nil)
    path = File.join(@root, PARTIAL)

    assert review.valid?(path, "_thing.scss")
    refute review.valid?(path, "thing.scss"), "a partial keeps its underscore"
    refute review.valid?(path, "_thing.css"), "the extension stays"
    refute review.valid?(path, "_zen_thing.scss"), "a rename changes the name"
    refute review.valid?(path, "_Thing.scss"), "snake_case only"
  end

  def test_the_proposal_must_survive_the_attack
    approving = stub_agent("RENAME: _thing.scss", "APPROVE")
    rejecting = stub_agent("RENAME: _thing.scss", "REJECT: it drops the brand the tree uses")
    path = File.join(@root, PARTIAL)

    assert_equal "_thing.scss", Master::Fix::NameReview.new(agent: approving).propose(path, reason: "test")
    assert_nil Master::Fix::NameReview.new(agent: rejecting).propose(path, reason: "test")
  end

  def test_suspect_names_are_reviewed_first
    sweep = Master::Fix::RenameSweep.new(agent: nil, repo_root: @root, review: Object.new, rename: Object.new)
    order = sweep.candidates("RAILS", "run-1").map { |path, _| File.basename(path) }

    assert_equal "_zen_thing.scss", order.first
    assert_includes order, "notes.md"
  end

  private

  def stub_agent(*answers)
    queue = answers.dup
    Object.new.tap { |agent| agent.define_singleton_method(:ask) { |_prompt, **| queue.shift } }
  end

  def write(rel, text)
    path = File.join(@root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def read(rel) = File.read(File.join(@root, rel))

  def git(*args)
    out, status = Open3.capture2e("git", "-C", @root, *args)
    raise "git #{args.first}: #{out}" unless status.success?

    out
  end
end
