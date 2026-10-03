# frozen_string_literal: true

require_relative "test_helper"

class TurnRouterTest < Minitest::Test
  def build_container(commands: nil)
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, **| text }
    {
      session: Struct.new(:budget_max, :cost).new(0, 0.0),
      agent: Struct.new(:model).new("test-model"),
      renderer:,
      commands: commands || { "status" => Master::CLI::CommandRegistry::Command.new { "status-ok" } },
      root: Dir.pwd,
      bus: nil,
    }
  end

  # Both, not just teardown. Clearing on the way out protects this file from
  # itself; clearing on the way in protects it from every other file, which is
  # where the leak actually came from (test_cli.rb builds tokenless CLIs).
  def setup
    Fiber[:master_visitor] = nil
  end

  def teardown
    Fiber[:master_visitor] = nil
  end

  # Security: ai.brgen.no serves the open internet, and AuthTier only *labels*
  # tokenless requests "visitor" rather than rejecting them. Everything past the
  # visitor check in TurnRouter.call can reach real capability — the Fold reaches
  # Core::World#do_exec with model-chosen argv, and infer_operator_command
  # reconstructs slash commands from plain English (defeating the leading-"/"
  # block in chat_controller#message). Visitors must land on casual_reply only.
# /fix is the verb that writes, and the words that mean "go through the tree
# and change it" are spellings of it. The reading words argue and change
# nothing. There is no /scan: a reading nobody acts on is what /fix absorbed.
def test_a_writing_word_reaches_fix_and_a_reading_word_reaches_the_council
  router = Master::CLI::TurnRouter

  assert_equal "/fix lib/io", router.rewrite_slash("/fix lib/io")
  assert_equal "/fix RAILS --no-autofix", router.rewrite_slash("/scan RAILS --no-autofix")
  assert_equal "/fix x", router.rewrite_slash("/sweep x")
  assert_equal "/fix", router.rewrite_slash("/triad")
  assert_equal "/review --only critique lib", router.rewrite_slash("/critique lib")
  assert_equal "/review --only critique lib", router.rewrite_slash("/council lib")
  assert_equal "/review master", router.rewrite_slash("/review master")
end

def test_scan_is_not_a_command_any_more
  router = Master::CLI::TurnRouter

  refute_includes router::PIPELINE_SLASH, "scan"
  refute_includes router::PIPELINE_COMMANDS, "scan"
  # An unknown slash is left alone; the registry answers it, and it has no scan.
  assert_equal "/scan lib/io", router.rewrite_slash("/scan lib/io")
end

# The RAILS constitutional gate asks for a reading it can grep and no writes.
# The flag rides along rather than being eaten as a path.
def test_a_read_only_fix_keeps_the_flag_the_rails_gate_passes
  rewritten = Master::CLI::TurnRouter.rewrite_slash("/fix --dry-run ../RAILS/amber")

  assert_equal "/fix --dry-run ../RAILS/amber", rewritten
end

  def test_a_file_read_is_not_casual_for_an_operator
    refute Master::CLI::TurnRouter.casual?("read CLAUDE.md")
  end

  def test_visitor_cannot_reach_fold_or_command_registry
    ["fix the bug", "run master through itself", "implement pagination for posts"].each do |message|
      Fiber[:master_visitor] = true
      reached = :none

      Master::CLI::TurnRouter.stub(:run_fold, ->(*, **) { reached = :fold; Master::Result.ok({ rendered: "" }) }) do
        Master::CLI::TurnRouter.stub(:dispatch_inferred, ->(*, **) { reached = :command; Master::Result.ok({ rendered: "" }) }) do
          Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { reached = :casual; Master::Result.ok({ rendered: "" }) }) do
            Master::CLI::TurnRouter.call(message:, container: build_container)
          end
        end
      end

      assert_equal :casual, reached, "visitor message #{message.inspect} escaped to #{reached}"
    end
  end

  def test_visitor_cannot_reach_media_intent
    Fiber[:master_visitor] = true
    reached = :none
    Master::Io::MediaIntent.stub(:dispatch, ->(*) { reached = :media; Master::Result.ok({ rendered: "" }) }) do
      Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { reached = :casual; Master::Result.ok({ rendered: "" }) }) do
        Master::CLI::TurnRouter.call(message: "generate a photo of bergen", container: build_container)
      end
    end
    assert_equal :casual, reached
  end

  def test_run_fold_refuses_visitors_directly
    Fiber[:master_visitor] = true
    result = Master::CLI::TurnRouter.run_fold("do something", container: build_container)

    assert result.err?
    assert_match(/not available to visitors/, result.message.to_s)
    assert_equal :policy, result.category
  end

  def test_authenticated_turns_still_reach_fold
    Fiber[:master_visitor] = nil
    reached = :none

    Master::CLI::TurnRouter.stub(:run_fold, ->(*, **) { reached = :fold; Master::Result.ok({ rendered: "" }) }) do
      Master::CLI::TurnRouter.call(message: "implement pagination for posts", container: build_container)
    end

    assert_equal :fold, reached
  end

  # A coding goal that Infer does not promote to an operator command: "fix the
  # bug" now routes to /fix via PIPELINE_COMMANDS, so it no longer reaches the
  # Fold. This message stays plain language all the way down.
  def test_plain_language_routes_to_fold
    fold = { reason: :complete, turns: 1, summary: "done", transcript: [] }
    Master.stub(:any_api_key_present?, true) do
      Master::CLI::CoreBridge.stub(:run, fold) do
        result = Master::CLI::TurnRouter.call(message: "implement pagination for posts", container: build_container)
        assert result.ok?, -> { "fold errored: #{result.message}" }
        assert_match(/fold0: complete/, result.value[:rendered])
      end
    end
  end

  def test_fix_language_is_promoted_to_operator_command_not_fold
    inferred = Master::CLI::TurnRouter.infer_operator_command("fix the bug", container: build_container)

    refute_nil inferred, "expected Infer to promote 'fix the bug' to an operator command"
    assert_includes Master::CLI::TurnRouter::PIPELINE_COMMANDS, inferred[:command]
  end

  def test_a_sentence_asking_to_fix_reaches_the_writing_verb
    inferred = Master::CLI::TurnRouter.infer_operator_command("can you fix and commit all these violations?",
                                                              container: build_container)

    assert_equal "fix", inferred[:command]
    assert_match(%r{\A/fix}, Master::CLI::TurnRouter.rewrite_slash("/#{inferred[:command]} #{inferred[:args]}"))
  end

  # The command is gone; the word people use for it still reaches the engine,
  # because asking to be told what is wrong is where a fix starts.
  def test_a_sentence_asking_to_scan_reaches_the_same_engine
    assert_equal "fix", Master::CLI::TurnRouter.send(:normalize_inferred_command, "scan", "scan lib/io")
  end

  def test_an_inferred_word_no_handler_takes_stays_a_sentence
    inferred = Master::CLI::TurnRouter.infer_operator_command("read lib/trace/dmesg.rb and summarise it",
                                                              container: build_container)

    assert_nil inferred, "no handler answers /dmesg, so the sentence must reach the model"
  end

  def test_slash_routes_to_command_registry
    calls = []
    pipeline = Object.new
    pipeline.define_singleton_method(:call) { |*| calls << :pipeline }
    Master::CLI::TurnRouter.call(message: "/status", container: build_container)
    assert_empty calls
  end

  def test_slash_status_renders_command_output
    result = Master::CLI::TurnRouter.call(message: "/status", container: build_container)
    assert result.ok?
    assert_match(/status-ok/, result.value[:rendered].to_s)
  end

  # ChatService builds image_payload from the upload token, but the face used
  # to drop it: TurnRouter.casual_reply never put :image on the agent ctx, so
  # a visitor who attached a photo talked to a model that could not see it.
  def test_casual_reply_forwards_image_to_the_agent
    image = { data: "abc", mime: "image/jpeg", name: "x.jpg" }
    seen = nil
    agent = Object.new
    agent.define_singleton_method(:call) do |ctx|
      seen = ctx
      Master::Result.ok("ok")
    end
    container = build_container.merge(agent:)

    Master.stub(:any_api_key_present?, true) do
      result = Master::CLI::TurnRouter.casual_reply("what is this", container:, image:)
      assert result.ok?
    end

    assert_equal image, seen[:image]
    assert_equal "what is this", seen[:message]
  end

  def test_run_promotes_to_fold
    fold = { reason: :complete, turns: 1, summary: "shipped", transcript: [] }
    Master.stub(:any_api_key_present?, true) do
      Master::CLI::CoreBridge.stub(:run, fold) do
        result = Master::CLI::TurnRouter.call(message: "/run add tests", container: build_container)
        assert result.ok?, -> { "fold errored: #{result.message}" }
        assert_match(/shipped/, result.value[:rendered])
      end
    end
  end
end
