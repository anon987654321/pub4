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
# One verb, named stages. The registry has carried a closed public surface for
# months — scan, fix and critique are methods ThroughPipeline calls, not slash
# verbs — but every one of those words rewrote to a bare /through, so asking to
# scan also ran the fix loop, the council and the principle map. Each word now
# carries the stage it names.
def test_each_stage_word_rewrites_to_its_own_stage
  router = Master::CLI::TurnRouter

  assert_equal "/through --only scan lib/io", router.rewrite_slash("/scan lib/io")
  assert_equal "/through --only scan lib/io", router.rewrite_slash("/fix lib/io")
  assert_equal "/through --only critique lib", router.rewrite_slash("/critique lib")
  assert_equal "/through --only critique lib", router.rewrite_slash("/council lib")
end

# The words that mean the whole pass still mean the whole pass, and a flag
# rides along rather than being eaten as a path.
def test_the_whole_pass_words_are_untouched
  router = Master::CLI::TurnRouter

  assert_equal "/through master", router.rewrite_slash("/through master")
  assert_equal "/through x", router.rewrite_slash("/sweep x")
  assert_equal "/through", router.rewrite_slash("/triad")
  assert_equal "/through --only scan --no-autofix ../RAILS/bsdports",
               router.rewrite_slash("/scan --no-autofix ../RAILS/bsdports")
end

# The RAILS constitutional gate shells `/scan --no-autofix <app>` and greps
# the violation line out of the output. A rewrite that dropped the flag, or
# that stopped running the aesthetic pass the budget is measured against,
# would change what four recorded ceilings compare to.
def test_the_scan_stage_keeps_the_flag_the_rails_gate_passes
  rewritten = Master::CLI::TurnRouter.rewrite_slash("/scan --no-autofix ../RAILS/amber")

  assert_includes rewritten, "--no-autofix"
  assert_includes rewritten, "--only scan"
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
  # bug" now routes to /fix via THROUGH_COMMANDS, so it no longer reaches the
  # Fold. This message stays plain language all the way down.
  def test_plain_language_routes_to_fold
    fold = { reason: :complete, turns: 1, summary: "done", transcript: [] }
    Master.stub(:any_api_key_present?, true) do
      Master::CLI::CoreBridge.stub(:run, fold) do
        result = Master::CLI::TurnRouter.call(message: "implement pagination for posts", container: build_container)
        assert result.ok?, -> { "fold errored: #{result.message}" }
        assert_match(/core: complete/, result.value[:rendered])
      end
    end
  end

  def test_fix_language_is_promoted_to_operator_command_not_fold
    inferred = Master::CLI::TurnRouter.infer_operator_command("fix the bug", container: build_container)

    refute_nil inferred, "expected Infer to promote 'fix the bug' to an operator command"
    assert_includes Master::CLI::TurnRouter::THROUGH_COMMANDS, inferred[:command]
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
    container = build_container.merge(agent: agent)

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
