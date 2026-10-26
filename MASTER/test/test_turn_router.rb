# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "shellwords"
require "tmpdir"

class TurnRouterTest < Minitest::Test
  def build_container(commands: nil, root: Dir.pwd)
    renderer = Object.new
    renderer.define_singleton_method(:render) { |text, **| text }
    {
      session: Struct.new(:budget_max, :cost).new(0, 0.0),
      agent: Struct.new(:model).new("test-model"),
      renderer:,
      commands: commands || { "status" => Master::CLI::CommandRegistry::Command.new { "status-ok" } },
      root:,
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
# nothing. /scan is only a spelling of /fix: a reading nobody acts on is what /fix absorbed.
# A question is answered, not dispatched: command inference would turn its words into a
# council review or a shell lookup.
def test_a_question_goes_to_the_agent_and_never_to_command_inference
  questions = ["In one sentence, what does MASTER/lib/face.rb do?",
               "Which file defines Master::Face::Contract.stipple_profile?",
               "why aren't you reading tts out loud?",
               "how do I run the review pass through master?",
               "is the council enabled"]
  questions.each do |message|
    reached = nil
    Master::CLI::TurnRouter.stub(:casual_reply, ->(*, **) { reached = :casual; Master::Result.ok({ rendered: "" }) }) do
      Master::CLI::TurnRouter.stub(:infer_operator_command, ->(*, **) { reached = :inferred; nil }) do
        Master::CLI::TurnRouter.call(message:, container: build_container)
      end
    end
    assert_equal :casual, reached, message
  end
end

def test_an_instruction_is_still_not_a_question
  refute Master::CLI::TurnRouter.question?("run the tests in lib/io")
  refute Master::CLI::TurnRouter.question?("review rails")
  assert Master::CLI::TurnRouter.question?("what is the current model")
end

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

def test_scan_is_a_spelling_of_fix_not_a_command
  router = Master::CLI::TurnRouter

  refute_includes router::PIPELINE_COMMANDS, "scan"
  assert_equal "/fix lib/io", router.rewrite_slash("/scan lib/io")
end

# The RAILS constitutional check asks for a reading it can grep and no writes.
# The flag rides along rather than being eaten as a path.
def test_a_read_only_fix_keeps_the_flag_the_rails_check_passes
  rewritten = Master::CLI::TurnRouter.rewrite_slash("/fix --dry-run ../RAILS/amber")

  assert_equal "/fix --dry-run ../RAILS/amber", rewritten
end

  def test_deployment_intent_understands_natural_variants
    router = Master::CLI::TurnRouter

    assert router.deployment_intent?("please deploy MASTER and RAILS and OPENBSD to vm23 --confirm")
    assert router.deployment_intent?("ship MASTER to production")
    assert router.deployment_intent?("put the Rails fleet live on vm23")
    assert router.deployment_intent?("release brgen to vm23 --confirm")
  end

  def test_deployment_intent_does_not_turn_status_questions_into_mutations
    router = Master::CLI::TurnRouter

    refute router.deployment_intent?("did the deploy work?")
    refute router.deployment_intent?("why did deploy fail?")
    refute router.deployment_intent?("check deploy status on vm23")
    refute router.deployment_intent?("deploy status on vm23")
  end

  def test_deployment_args_maps_fleet_language_to_all
    router = Master::CLI::TurnRouter

    assert_equal "all --confirm", router.deployment_args("ship MASTER and RAILS to vm23 --confirm")
    assert_equal "all", router.deployment_args("put the whole stack live on vm23")
    assert_equal "brgen --confirm", router.deployment_args("release brgen to production --confirm")
  end

  def test_deploy_confirmation_survives_natural_language_routing
    args = Master::CLI::TurnRouter.deployment_args(
      "please deploy MASTER and RAILS and OPENBSD to vm23 --confirm",
    )

    assert_equal "all --confirm", args
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

  def test_public_site_news_request_uses_tool_capable_chat_not_fold
    message = "Go to www.nrk.no, give me today's news in norwegian"
    reached = :none

    Master::CLI::TurnRouter.stub(:casual_reply, lambda { |text, **|
      reached = :chat
      Master::Result.ok({ rendered: text })
    }) do
      Master::CLI::TurnRouter.stub(:run_fold, ->(*) { reached = :fold; flunk "read-only web research must not enter the coding fold" }) do
        result = Master::CLI::TurnRouter.call(message:, container: build_container)

        assert result.ok?
        assert_equal :chat, reached
        assert_equal message, result.value[:rendered]
      end
    end
  end

  def test_public_site_request_with_mutating_intent_is_not_classified_as_research
    refute Master::CLI::TurnRouter.public_research_request?(
      "Go to https://example.com and publish this post",
    )
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

  # /fix writes code; a person asking about a heater or a bike is not asking for it.
  def test_fix_about_things_that_are_not_code_is_not_the_command
    fix = Master::CLI::TurnRouter::FIX_COMMAND

    ["fix the heater in my flat", "fix my bike", "fix it", "fixing things is hard"].each do |text|
      refute_match fix, text
    end

    ["fix", "fix lib/cli", "fix rails", "fix the failing tests", "fix the lint violations"].each do |text|
      assert_match fix, text
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

  def test_slash_command_context_keeps_the_turn_cancellation_token
    token = Master::Core::CancellationToken.new
    seen = nil
    command = Master::CLI::CommandRegistry::Command.new do |ctx|
      seen = ctx.cancellation
      "status-ok"
    end
    container = build_container(commands: { "status" => command })

    result = Master::CLI::TurnRouter.call(message: "/status", container:, cancellation: token)

    assert result.ok?
    assert_same token, seen
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
  # Regression: this natural-language media request must not fall through into
  # operator-command inference, where the opening word "make" was once treated
  # as a shell command. A paid video remains a dry run until confirmed.
  def test_lora_video_request_is_dispatched_before_command_inference
    Dir.mktmpdir("turn-router-lora") do |root|
      still = File.join(root, "STUDIO", "replicate", "lora", "johann", "out", "07.jpg")
      FileUtils.mkdir_p(File.dirname(still))
      File.write(still, "fixture")

      calls = []
      fake_dispatch = lambda do |root:, tool:, arg:, env: {}|
        calls << { root:, tool:, argv: Shellwords.split(arg) }
        Master::Result.ok("lora: planned")
      end

      Master::Io::ScriptDispatch.stub(:run, fake_dispatch) do
        Master::CLI::TurnRouter.stub(:infer_operator_command, ->(*) { raise "media intent fell through to command inference" }) do
          result = Master::CLI::TurnRouter.call(
            message: "make a video with the lora of me from #{still}",
            container: build_container(root:)
          )
          assert result.ok?, -> { result.message.to_s }
        end
      end

      assert_equal 1, calls.length
      assert_equal "lora", calls.first[:tool]
      assert_includes calls.first[:argv], "--video-replicate"
      assert_includes calls.first[:argv], "--dry-run"
    end
  end

  def test_fold_result_preserves_cancellation_and_ambiguous_outcome_categories
    cancelled = Master::CLI::TurnRouter.fold_to_result(
      reason: :cancelled, turns: 1, summary: "cancelled", transcript: []
    )
    audit_failed = Master::CLI::TurnRouter.fold_to_result(
      reason: :trace_failed, turns: 1, summary: "after-event failed", transcript: []
    )
    unknown = Master::CLI::TurnRouter.fold_to_result(
      reason: :unknown_outcome, turns: 1, summary: "receipt missing", transcript: []
    )
    recovery_failed = Master::CLI::TurnRouter.fold_to_result(
      reason: :recovery_failed, turns: 1, summary: "rollback unproven", transcript: []
    )
    approval = Master::CLI::TurnRouter.fold_to_result(
      reason: :needs_user, turns: 1, summary: "approval unavailable", transcript: []
    )

    assert_equal :cancelled, cancelled.category
    assert_equal :unknown_outcome, audit_failed.category
    assert_equal :unknown_outcome, unknown.category
    assert_equal :recovery_failed, recovery_failed.category
    assert_equal :human_decision, approval.category
    [cancelled, audit_failed, unknown, recovery_failed, approval].each { |result| refute result.ok? }
  end

  def test_inferred_slash_route_retains_the_active_cancellation_token
    token = Master::Core::CancellationToken.new
    container = build_container
    captured = nil
    dispatcher = lambda do |input, container:, felt_sense: nil, on_turn: nil, cancellation: nil|
      captured = { input:, cancellation: }
      Master::Result.ok({ rendered: "routed" })
    end

    Master::CLI::TurnRouter.stub(:dispatch_slash, dispatcher) do
      result = Master::CLI::TurnRouter.dispatch_inferred(
        { command: "run", args: "read README.md", confidence: 0.9 },
        container:, cancellation: token
      )
      assert result.ok?
    end

    assert_equal "/run read README.md", captured[:input]
    assert_same token, captured[:cancellation]
  end

  def test_fold_routing_activates_cooperative_cancellation_before_setup
    token = Master::Core::CancellationToken.new
    Master.stub(:llm_reachable?, false) do
      result = Master::CLI::TurnRouter.run_fold(
        "inspect the project", container: build_container, cancellation: token
      )
      refute result.ok?
      assert_predicate token, :active?
    end
  end

end
