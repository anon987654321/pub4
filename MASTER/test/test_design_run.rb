# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/design_run"

class TestDesignRun < Minitest::Test
  RUN = Operator::DesignRun
  Surface = Struct.new(:id, :pixel_snapshot)
  Round = Struct.new(:outcome)

  def said(kept, surfaces)
    lines = []
    RUN.stub(:say, ->(text) { lines << text }) { RUN.baselines_note(kept, surfaces) }
    lines
  end

  # Baseline approval is the operator's, so a run that kept an edit names what to review first.
  def test_a_kept_edit_names_the_measured_surfaces_that_carry_an_approved_png
    surfaces = [Surface.new("amber/home/desktop", true), Surface.new("amber/feed/desktop", false)]
    lines = said([Round.new(:kept)], surfaces)

    assert_match(/differ on: amber\/home\/desktop\z/, lines.first)
    assert_match(/approve_visual_baselines\.rb --manifest/, lines.last)
  end

  def test_nothing_is_said_without_a_kept_edit_or_without_an_approved_png
    assert_empty said([], [Surface.new("amber/home/desktop", true)])
    assert_empty said([Round.new(:kept)], [Surface.new("amber/feed/desktop", false)])
  end

  def git(root, *args) = system("git", "-C", root, *args, out: File::NULL, err: File::NULL)

  def write_all(root, files) = files.each { |rel, text| File.write(File.join(root, rel), text) }

  # A checkout whose MASTER declares data/laws.yml sacred, with laws.yml and app.css edited since its base commit.
  def edited_checkout(root)
    git(root, "init", "-q")
    git(root, "config", "user.email", "test@example.invalid")
    git(root, "config", "user.name", "test")

    FileUtils.mkdir_p(File.join(root, "MASTER", "data"))
    File.write(File.join(root, "MASTER", "data", "soul.yml"), "absolute:\n  sacred_paths:\n    - data/laws.yml\n")
    write_all(root, "MASTER/data/laws.yml" => "a: 1\n", "app.css" => "a {}\n")
    git(root, "add", ".")
    git(root, "commit", "-q", "-m", "base")

    write_all(root, "MASTER/data/laws.yml" => "a: 2\n", "app.css" => "b {}\n")
  end

  # A design run commits unattended, so it goes through git! and a sacred path is refused there.
  def test_commit_refuses_a_sacred_path_and_commits_an_ordinary_one
    Dir.mktmpdir do |root|
      edited_checkout(root)
      lines = []

      RUN.stub(:say, ->(text) { lines << text }) do
        refute RUN.commit(File.join(root, "MASTER", "data", "laws.yml"), "design: laws", root:)
        assert RUN.commit(File.join(root, "app.css"), "design: css", root:)
      end

      assert_match(/data\/laws\.yml is sacred/, lines.first)
      assert_equal "design: css\nbase\n", IO.popen(["git", "-C", root, "log", "--format=%s"], &:read)
    end
  end
end
