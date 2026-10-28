# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/agent_context"
require "open3"

class TestSoul < Minitest::Test
  Agent = Struct.new(:draft) do
    def ask_once(*) = draft
  end

  # Every rule reaches the model that has to obey it, and there is one place
  # they come from.
  #
  # soul carried absolute.rules and absolute.aesthetic_rules. The second reached
  # nothing but fix/repair_loop, so NO_ASCII_DECORATION, FLAT_UI and DEEP_SCAN_ONLY
  # governed the fixer's rewrites while the model writing the code was never told
  # them. Then both moved to law/, once the `conduct` kind let a rule about how
  # to work be a Law like any other — a rule the author cannot see is a rule the
  # fixer spends its turn undoing, and a rule in two files is one a reader cannot
  # resolve.
  def test_every_rule_reaches_the_system_prompt_from_one_registry
    prompt = Master::Voice::Personality.new.send(:build_system_prompt, context: :full)
    absolute = Master.load_yaml(Master.data_path("soul.yml")).fetch("absolute")

    %w[rules aesthetic_rules].each do |key|
      refute absolute.key?(key), "soul must not hold rules; law/ is the registry"
    end

    laws = Master::Ground::Laws.new.laws
    refute_empty laws, "law/ must load"
    missing = laws.keys.reject { |id| prompt.include?(id) }
    assert_empty missing, "laws absent from the prompt: #{missing.first(5).join(', ')}"
  end

  # The counterweight to the assertion above, and the reason it was needed. That
  # test holds soul.yml empty of rules; nothing held their readers to the move.
  # tools/agent_context.rb — the file every harness contract sends an agent to —
  # went on digging for `absolute.rules`, got nil, and printed its heading over
  # an empty list. Assert what the section says, not that the key is gone.
  def test_the_conduct_rules_reach_the_agent_context
    conduct = Operator::AgentContext.conduct

    assert_operator conduct.size, :>, 40, "law/practice.rb holds the rules that left soul"
    assert_includes conduct.keys, "PRESERVE_FIRST"
    assert_includes Operator::AgentContext.render, "PRESERVE_FIRST: never rewrite working code"
  end

  DOCUMENT = <<~SOUL
    Version: 1.2.3
    Persona: Malay
    Voice: Terse. Direct. Dark.

    ## Values
    The golden rule is preserve then improve.
    The anti-simulation rule requires evidence.
    Voice character remains terse, direct, dark.

    ## Changelog
    | Version | Date | Change | Approval |
    | 1.0.0 | 2025-01-01 | Initial | Initial |
  SOUL

  def setup
    @root = Dir.mktmpdir("master-soul-")
    FileUtils.mkdir_p(File.join(@root, "data"))
    File.write(File.join(@root, "data", "SOUL.md"), DOCUMENT)
  end

  def teardown = FileUtils.rm_rf(@root)

  def test_proposal_uses_instance_root_and_reject_removes_it
    soul = Master::Voice::Soul.new(root: @root, agent: Agent.new(DOCUMENT + "\nA small clarification.\n"))

    assert_match(/proposal saved/, soul.propose("clarify"))
    assert File.file?(File.join(@root, ".master", "soul_proposal.md"))
    assert_equal "proposal rejected", soul.reject
    refute File.exist?(File.join(@root, ".master", "soul_proposal.md"))
  end

  def test_proposal_blocks_removal_of_absolute_principle
    unsafe = DOCUMENT.sub(/The golden rule.*\n/, "")
    soul = Master::Voice::Soul.new(root: @root, agent: Agent.new(unsafe))

    assert_match(/BLOCKED/, soul.propose("remove a principle"))
    refute File.exist?(File.join(@root, ".master", "soul_proposal.md"))
  end

  # A proposal edited on disk after `propose` accepted it must not carry an
  # absolute section out of SOUL.md at approval.
  def test_approve_refuses_a_proposal_that_drops_an_absolute_section
    soul = Master::Voice::Soul.new(root: @root)
    soul.define_singleton_method(:commit_approval) { flunk "approval must not commit" }
    proposal = File.join(@root, ".master", "soul_proposal.md")
    FileUtils.mkdir_p(File.dirname(proposal))
    File.write(proposal, DOCUMENT.sub(/The anti-simulation rule.*\n/, ""))

    assert_match(/BLOCKED/, soul.approve)
    assert_equal DOCUMENT, File.read(File.join(@root, "data", "SOUL.md"))
  end

  def test_system_prompt_carries_identity_judgment_and_boundaries
    prompt = Master::Voice::Soul.new.system_prompt

    assert_includes prompt, "MASTER is not a mascot, oracle, or corporate assistant."
    assert_includes prompt, "Challenge an instruction when the proposed action conflicts with stronger authority"
    assert_includes prompt, "Do not invent capabilities, measurements, completion, or provenance."
  end

  def test_soul_yaml_contains_only_live_kernel_sections
    data = Master.load_yaml(Master.data_path("soul.yml"))

    refute data.key?("evolution_log"), "Git is the history of soul.yml"
    refute data.key?("research"), "research belongs outside the live soul kernel"
    refute data.fetch("negotiable").key?("tts_voice"), "voice has one authority at the top level"
    assert_equal %w[schema version persona voice language absolute prompt_ordering negotiable hooks], data.keys
  end

  # /soul printed "SOUL.md v1.0.0 | persona:" while the boot said rev 2.8.0.
  def test_summary_names_the_booted_revision_and_persona
    summary = Master::Voice::Soul.new.summary
    law = Master.load_yaml(Master.data_path("soul.yml"))

    assert summary.start_with?("soul0: rev #{law['version']}, persona #{law['persona']}\n"), summary
    assert_match(/\A# SOUL\z/, File.readlines(File.join(Master::ROOT, "data", "SOUL.md"), encoding: "UTF-8").first&.chomp)
    assert_includes File.read(File.join(Master::ROOT, "data", "SOUL.md"), encoding: "UTF-8"), "Be the assistant you'd actually want to talk to at 2am"

  end

  # SOUL.md carries no Version line, so approval must not invent one: the
  # revision it makes is the commit, and the reply and /soul version name it.
  def test_approve_names_the_commit_it_made
    with_git_identity do
      git("init", "-q")
      git("add", "data/SOUL.md")
      git("commit", "-q", "-m", "seed")
      draft = "#{DOCUMENT}\nA small clarification.\n"
      soul = Master::Voice::Soul.new(root: @root, agent: Agent.new(draft))
      soul.propose("clarify")

      reply = with_terminal_yes { soul.approve }
      head = git("rev-parse", "--short", "HEAD").strip

      assert_equal "soul updated in #{head}", reply
      assert_equal draft.strip, File.read(File.join(@root, "data", "SOUL.md"))
      assert_match(/\A#{head} \S+ Soul: evolution protocol update/, soul.changelog)
    end
  end

  # The index is shared with every session in the checkout: approval commits SOUL.md
  # and leaves what someone else staged staged and uncommitted.
  def test_approve_commits_only_soul_md
    with_git_identity do
      git("init", "-q")
      File.write(File.join(@root, "theirs.rb"), "A = 1\n")
      git("add", "data/SOUL.md", "theirs.rb")
      git("commit", "-q", "-m", "seed")

      File.write(File.join(@root, "theirs.rb"), "A = 2\n")
      git("add", "theirs.rb")

      soul = Master::Voice::Soul.new(root: @root, agent: Agent.new("#{DOCUMENT}\nA small clarification.\n"))
      soul.propose("clarify")

      assert_match(/\Asoul updated in /, with_terminal_yes { soul.approve })
      assert_equal "data/SOUL.md\n", git("show", "--name-only", "--format=", "HEAD")
      assert_equal "theirs.rb\n", git("diff", "--cached", "--name-only")
    end
  end

  # SOUL.md is sacred: with no person at a terminal to say yes (a web request, a
  # script), approval writes the file and commits nothing.
  def test_approve_without_a_terminal_yes_commits_nothing
    with_git_identity do
      git("init", "-q")
      git("add", "data/SOUL.md")
      git("commit", "-q", "-m", "seed")
      soul = Master::Voice::Soul.new(root: @root, agent: Agent.new("#{DOCUMENT}\nA small clarification.\n"))
      soul.propose("clarify")

      reply = Master::Io::GitOperations.stub(:confirm_at_terminal, nil) { soul.approve }

      assert_match(/not committed/, reply)
      assert_equal "seed", git("log", "-1", "--format=%s").strip
    end
  end

  # The operator's yes at the terminal, as confirm_at_terminal returns it.
  def with_terminal_yes(&)
    yes = ->(paths, **) { Master::Io::GitOperations::OperatorConfirmation.new(paths:) }
    Master::Io::GitOperations.stub(:confirm_at_terminal, yes, &)
  end

  GIT_IDENTITY = %w[GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL].freeze

  def with_git_identity
    saved = GIT_IDENTITY.to_h { |key| [key, ENV[key]] }
    GIT_IDENTITY.each { |key| ENV[key] = key.end_with?("EMAIL") ? "soul@example.test" : "soul" }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def git(*args)
    out, status = Open3.capture2e("git", "-C", @root, *args)
    assert status.success?, out
    out
  end
end
