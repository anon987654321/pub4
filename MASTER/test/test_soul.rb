# frozen_string_literal: true

require_relative "test_helper"

class TestSoul < Minitest::Test
  Agent = Struct.new(:draft) do
    def ask_once(*) = draft
  end

  # Every axiom soul declares must reach the model that has to obey it.
  #
  # absolute.rules arrived through PersonalityPromptBuilder#add_rules while a
  # second section, absolute.aesthetic_rules, arrived nowhere: its only reader
  # was fix/rule_loop.rb. So NO_ASCII_DECORATION, FLAT_UI, STRUNK_ACTIVE and
  # DEEP_SCAN_ONLY governed the fix loop's rewrites while the model writing the
  # code was never told them — 30 of 30 against 0 of 19. A rule the author
  # cannot see is a rule the fixer spends its turn undoing.
  #
  # The second section is gone rather than given a second reader: nothing ever
  # read the split as a distinction, and why_explainer dug only the first, so
  # /why on any of the nineteen answered nothing at all.
  def test_every_absolute_axiom_reaches_the_system_prompt
    prompt = Master::Voice::Personality.new.send(:build_system_prompt, context: :full)
    absolute = YAML.safe_load_file(Master.data_path("soul.yml")).fetch("absolute")

    refute absolute.key?("aesthetic_rules"),
           "one list: a split nothing reads is a section /why cannot reach"

    missing = absolute.fetch("rules").keys.reject { |id| prompt.include?(id) }
    assert_empty missing, "soul absolute.rules not in the prompt: #{missing.join(', ')}"
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

  def test_approve_updates_version_at_instance_root
    draft = DOCUMENT + "\nA small clarification.\n"
    soul = Master::Voice::Soul.new(root: @root, agent: Agent.new(draft))
    soul.define_singleton_method(:commit_approval) { |_version| true }

    soul.propose("clarify")
    assert_equal "soul updated to v1.2.4", soul.approve
    assert_includes File.read(File.join(@root, "data", "SOUL.md")), "Version: 1.2.4"
  end
end
