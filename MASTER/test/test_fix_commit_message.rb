# frozen_string_literal: true

require_relative "test_helper"

# /fix committed "Fix_loop: fast-fix [pass 1]" and "ABC_SIZE in baymard_law.rb" with a one-line body.
# Every /fix commit now satisfies data/commit_format.yml through Ground::CommitFormat, the checker the
# commit-msg hook asks, and carries a body saying what changed and why.
class TestFixCommitMessage < Minitest::Test
  Message = Master::Fix::CommitMessage

  def full(message) = "#{message}\n\n#{Master::Core::World::COMMIT_TRAILER}"

  def test_the_old_subjects_are_refused
    old_subjects = ["Fix_loop: fast-fix [pass 1]", "ABC_SIZE in baymard_law.rb\n\nABC_SIZE baymard_law.rb:23"]
    old_subjects.each do |old|
      refute_empty Message.problems(old), old
    end
  end

  def every_message
    Message::PASS_SHAPES.keys.map { |kind| Message.pass(kind, 12) } <<
      Message.repair(law: "ABC_SIZE", file: "checks/lib/research/baymard_law.rb", line: 23)
  end

  def test_every_pass_message_and_a_repair_satisfy_the_commit_format
    every_message.each do |message|
      assert_empty Master::Ground::CommitFormat.problems(full(message)), message
      assert_empty Message.problems(message), message
      assert message.lines.all? { |line| line.chomp.size <= 72 }, message
    end
  end

  def test_no_message_reads_as_a_refactor_claim_to_the_intent_check
    intent = Master::Ground::PreserveUserIntent.new
    every_message.each { |message| refute intent.refactor_message?(message), message }
  end

  def test_a_long_subject_is_cut_at_a_word
    message = Message.compose("Repair #{"VERY_LONG_LAW_NAME " * 6}in file.rb", what: "Changed it", why: "It was wrong")

    assert_operator message.lines.first.chomp.size, :<=, 72
    assert_empty Message.problems(message)
  end

  OneFileGit = Struct.new(:commits) do
    def changed_paths = ["ok.rb"]
    def commit(message, paths:) = commits << [message, paths]
  end

  def test_the_committer_refuses_a_message_that_breaks_the_format_before_staging
    Dir.mktmpdir do |root|
      File.write(File.join(root, "ok.rb"), "OK = 1\n")
      git = OneFileGit.new([])
      committer = Master::Fix::FixLoop::Committer.new(git:, root:)

      assert_raises(ArgumentError) { committer.send(:commit_scoped, "fix_loop: pass 1", paths: ["ok.rb"]) }
      assert_empty git.commits
    end
  end
  # A repair of three Laws ran past 72 characters, and the cut subject ended on "in" with the
  # file gone; the body carried the checkout's absolute path and was cut mid-name at 240.
  def test_a_many_law_repair_keeps_the_file_and_names_it_from_the_repo_root
    file = File.join(Master::REPO_ROOT, "RAILS/brgen/app/assets/stylesheets/_brgen_core_shell.scss")
    text = Master::Fix::CommitMessage.repair(law: "MOBILE_FIRST+NO_ASCII_LINE_ART+SMALL_FILES", file:, line: 6)
    subject, = text.lines

    assert_equal "Repair MOBILE_FIRST and 2 more in _brgen_core_shell.scss\n", subject
    assert_includes text, "rewrote RAILS/brgen/app/assets/stylesheets/_brgen_core_shell.scss"
    refute_includes text, Master::REPO_ROOT
    assert_includes text.gsub("\n", " "), "MOBILE_FIRST, NO_ASCII_LINE_ART and SMALL_FILES findings"
  end

end
