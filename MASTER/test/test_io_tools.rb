# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "rbconfig"

# The LLM-callable adapters in lib/io/ that DEFAULT_TOOL_MAP builds, and the
# small Io modules around them, driven through their public calls. Nothing here
# opens a socket or a browser: the network edge is stubbed at the one method
# that would reach it, so each test proves the decision made before that edge.
class TestIoTools < Minitest::Test
  Governor = Struct.new(:answer, :asked) do
    def permit?(name, tier, detail)
      (self.asked ||= []) << [name, tier, detail]
      answer
    end
  end

  Bus = Struct.new(:events) do
    def publish(name, **payload) = (self.events ||= []) << [name, payload]
    def names = Array(events).map(&:first)
  end

  def allow = Governor.new(Master::Result.ok("permitted"))
  def deny = Governor.new(Master::Result.err("denied", category: :policy))

  # realpath, because the tools realpath their root; on macOS /var is a symlink.
  def with_root
    Dir.mktmpdir("io_tools") { |raw| yield File.realpath(raw) }
  end

  def write(root, rel, text)
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
    path
  end

  # --- BatchReplace -----------------------------------------------------------

  def test_batch_replace_rewrites_every_matching_file_under_the_root
    with_root do |root|
      a = write(root, "notes/a.txt", "old words\n")
      b = write(root, "notes/deep/b.md", "the old way\n")
      untouched = write(root, "notes/c.txt", "nothing here\n")

      result = Master::Io::BatchReplace.new(root:, governor: allow).call(old_str: "old", new_str: "new")

      assert result.ok?, result.to_s
      assert_equal "replaced in 2 file(s)", result.value!
      assert_equal "new words\n", File.read(a)
      assert_equal "the new way\n", File.read(b)
      assert_equal "nothing here\n", File.read(untouched)
    end
  end

  def test_batch_replace_writes_nothing_when_the_governor_refuses
    with_root do |root|
      path = write(root, "a.txt", "old\n")

      result = Master::Io::BatchReplace.new(root:, governor: deny).call(old_str: "old", new_str: "new")

      refute result.ok?
      assert_equal "old\n", File.read(path)
    end
  end

  def test_batch_replace_refuses_a_directory_outside_the_root
    with_root do |root|
      result = Master::Io::BatchReplace.new(root:, governor: allow).call(old_str: "a", new_str: "b", dir: "../..")

      refute result.ok?
      assert_match(/escapes root/, result.message)
    end
  end

  def test_batch_replace_leaves_sacred_paths_alone
    with_root do |root|
      sacred = write(root, "data/config.yml", "old: 1\n")
      ordinary = write(root, "lib/x.txt", "old\n")

      Master::Io::BatchReplace.new(root:, governor: allow).call(old_str: "old", new_str: "new")

      assert_equal "old: 1\n", File.read(sacred)
      assert_equal "new\n", File.read(ordinary)
    end
  end

  def test_batch_replace_renames_files_only_when_asked
    with_root do |root|
      write(root, "old_name.txt", "x\n")
      tool = Master::Io::BatchReplace.new(root:, governor: allow)

      tool.call(old_str: "old_name", new_str: "new_name")
      assert File.exist?(File.join(root, "old_name.txt"))

      tool.call(old_str: "old_name", new_str: "new_name", rename_files: true)
      assert File.exist?(File.join(root, "new_name.txt"))
      refute File.exist?(File.join(root, "old_name.txt"))
    end
  end

  # --- SearchKnowledge ---------------------------------------------------------

  def test_search_knowledge_reads_knowledge_and_never_docs
    with_root do |root|
      write(root, "knowledge/openbsd/pledge.md", "pledge(2) restricts syscalls\n")
      write(root, "docs/pledge.md", "pledge in the wrong directory\n")

      result = Master::Io::SearchKnowledge.new(root:).call(query: "pledge")

      assert result.ok?, result.to_s
      assert_match(%r{### openbsd/pledge\.md:1}, result.value!)
      refute_match(/wrong directory/, result.value!)
    end
  end

  def test_search_knowledge_says_so_when_there_is_no_knowledge_base
    with_root do |root|
      write(root, "docs/pledge.md", "pledge\n")

      result = Master::Io::SearchKnowledge.new(root:).call(query: "pledge")

      refute result.ok?
      assert_equal "knowledge base not found", result.message
    end
  end

  # A realpath prefix check let ../knowledge_old through, because
  # "/root/knowledge_old" starts with "/root/knowledge".
  def test_search_knowledge_refuses_a_topic_that_climbs_into_a_sibling_directory
    with_root do |root|
      write(root, "knowledge/ruby/a.md", "fine\n")
      write(root, "knowledge_old/secret.md", "secret token\n")

      result = Master::Io::SearchKnowledge.new(root:).call(query: "secret", topic: "../knowledge_old")

      refute result.ok?, "a sibling that shares the prefix is outside knowledge/"
      assert_match(/unknown topic/, result.message)
    end
  end

  def test_search_knowledge_treats_an_invalid_regexp_as_a_literal
    with_root do |root|
      write(root, "knowledge/a.md", "call foo( here\n")

      result = Master::Io::SearchKnowledge.new(root:).call(query: "foo(")

      assert result.ok?, result.to_s
      assert_match(/1 matches/, result.value!)
    end
  end

  # --- WebSearch ---------------------------------------------------------------

  Response = Struct.new(:code, :body)

  def test_web_search_asks_the_governor_before_any_request
    tool = Master::Io::WebSearch.new(governor: deny)
    tool.define_singleton_method(:fetch_search_response) { |_q| raise "must not fetch" }

    result = tool.call(query: "openbsd")

    refute result.ok?
    assert_equal "denied", result.message
  end

  def test_web_search_truncates_a_long_query_and_extracts_the_answer
    governor = allow
    bus = Bus.new
    tool = Master::Io::WebSearch.new(governor:, event_bus: bus)
    body = { "Abstract" => "OpenBSD is secure", "RelatedTopics" => [{ "Text" => "pledge" }, {}] }.to_json
    seen = nil
    tool.define_singleton_method(:fetch_search_response) { |q| seen = q; Response.new("200", body) }

    result = tool.call(query: "x" * 400)

    assert result.ok?, result.to_s
    assert_equal "OpenBSD is secure\n\npledge", result.value!
    assert_equal Master::Io::WebSearch::MAX_QUERY_CHARS, seen.length
    assert_includes bus.names, "tool:warning"
  end

  def test_web_search_reports_a_non_200_as_infrastructure
    tool = Master::Io::WebSearch.new(governor: allow)
    tool.define_singleton_method(:fetch_search_response) { |_q| Response.new("503", "") }

    result = tool.call(query: "q")

    refute result.ok?
    assert_equal :infrastructure, result.category
    assert_match(/HTTP 503/, result.message)
  end

  # --- AskLlm ------------------------------------------------------------------

  class Breaker
    def call(_cost) = yield
  end

  class Cache
    def initialize(hit = nil) = @hit = hit
    def fetch(_prompt, _model) = @hit || yield
  end

  class Agent
    attr_reader :asked

    def model = "test-model"
    def ask(prompt, context:) = (@asked = [prompt, context]) && "answer to #{prompt}"
  end

  def ask_llm(governor: allow, cache: Cache.new, agent: Agent.new)
    Master::Io::AskLlm.new(agent:, governor:, circuit_breaker: Breaker.new, cache:)
  end

  # The cost estimate named Review::Agent::COST_PER_TOKEN, which does not exist,
  # so every call ended in NameError inside the rescue and came back as an Err.
  def test_ask_llm_returns_the_agent_answer
    agent = Agent.new
    result = ask_llm(agent:).call(prompt: "why", context: ["c"])

    assert result.ok?, result.to_s
    assert_equal "answer to why", result.value!
    assert_equal ["why", ["c"]], agent.asked
  end

  def test_ask_llm_serves_a_cache_hit_without_asking_the_agent
    agent = Agent.new
    result = ask_llm(cache: Cache.new("cached"), agent:).call(prompt: "why")

    assert_equal "cached", result.value!
    assert_nil agent.asked
  end

  def test_ask_llm_refused_by_the_governor_never_reaches_the_agent
    agent = Agent.new
    result = ask_llm(governor: deny, agent:).call(prompt: "why")

    refute result.ok?
    assert_nil agent.asked
  end

  def test_ask_llm_turns_an_agent_exception_into_an_err
    agent = Agent.new
    agent.define_singleton_method(:ask) { |*_a, **_k| raise "provider down" }

    result = ask_llm(agent:).call(prompt: "why")

    refute result.ok?
    assert_equal "ask_llm: provider down", result.message
  end

  # --- GitContext --------------------------------------------------------------

  def with_repo
    with_root do |root|
      git = ->(*args) { system("git", "-C", root, *args, out: File::NULL, err: File::NULL) || flunk("git #{args.join(' ')}") }
      git.call("init", "-q")
      git.call("config", "user.email", "t@example.com")
      git.call("config", "user.name", "t")
      write(root, "a.txt", "one\n")
      git.call("add", "a.txt")
      git.call("commit", "-q", "-m", "first commit")
      yield root
    end
  end

  def test_git_context_summarises_status_and_log
    with_repo do |root|
      tool = Master::Io::GitContext.new(root:)
      assert_equal "(clean)", tool.call(operation: "status").value!

      write(root, "a.txt", "two\n")
      assert_match(/\bM a\.txt/, tool.call(operation: "status").value!)
      assert_match(/first commit/, tool.call(operation: "log", limit: 1).value!)
      assert_match(/1\) two$/, tool.call(operation: "blame", path: "a.txt").value!)
      assert_match(/a\.txt/, tool.call(operation: "diff").value!)
      assert_match(/first commit/, tool.call(operation: "show").value!)
    end
  end

  def test_git_context_refuses_a_path_outside_the_root_and_a_blob_ref
    with_repo do |root|
      tool = Master::Io::GitContext.new(root:)

      escape = tool.call(operation: "log", path: "../../etc/passwd")
      refute escape.ok?
      assert_match(/escapes root/, escape.message)

      blob = tool.call(operation: "show", path: "HEAD:a.txt")
      refute blob.ok?
      assert_match(/must name a commit/, blob.message)
    end
  end

  def test_git_context_rejects_an_unknown_operation
    with_root do |root|
      result = Master::Io::GitContext.new(root:).call(operation: "push")

      refute result.ok?
      assert_equal :validation, result.category
    end
  end

  # --- McpCoordinator ----------------------------------------------------------

  class FakeClient
    attr_reader :started

    def start = @started = true
    def tools = [Struct.new(:name, :description).new("read", "reads")]
  end

  def mcp(root, bus, &factory)
    coordinator = Master::Io::McpCoordinator.new(root:, event_bus: bus)
    coordinator.define_singleton_method(:build_mcp_client, &factory) if factory
    coordinator
  end

  def test_mcp_with_no_config_connects_nothing_and_says_so
    with_root do |root|
      bus = Bus.new
      mcp(root, bus).connect_all

      assert_equal [["mcp:connected", { count: 0 }]], bus.events
    end
  end

  def test_mcp_skips_disabled_servers_and_isolates_a_failing_one
    with_root do |root|
      write(root, "data/mcp_servers.yml", <<~YAML)
        servers:
          off: { enabled: false, command: npx }
          good: { command: npx }
          bad: { command: npx }
      YAML
      bus = Bus.new
      built = []
      coordinator = mcp(root, bus) do |name, _transport, _config|
        built << name
        raise "spawn failed" if name == "bad"

        FakeClient.new
      end

      coordinator.connect_all

      assert_equal %w[good bad], built, "a disabled server is never built"
      assert_includes bus.events, ["mcp:server_failed", { name: "bad", error: "spawn failed" }]
      assert_includes bus.events, ["mcp:connected", { count: 1 }]
    end
  end

  # --- IngressRunner -----------------------------------------------------------

  FIBER_KEYS = %i[master_elevated master_visitor master_paired master_pair_subject].freeze

  def with_clean_fiber
    FIBER_KEYS.each { |k| Fiber[k] = nil }
    yield
  ensure
    FIBER_KEYS.each { |k| Fiber[k] = nil }
  end

  def test_ingress_runner_clears_fiber_trust_even_when_the_turn_raises
    with_clean_fiber do
      seen = nil
      gateway = Object.new
      gateway.define_singleton_method(:receive) do |**_kw|
        seen = [Fiber[:master_elevated], Fiber[:master_visitor]]
        Fiber[:master_paired] = true
        raise "boom"
      end

      assert_raises(RuntimeError) do
        Master::Io::IngressRunner.run_turn(container: { gateway: }, message: "hi", elevated: true)
      end

      assert_equal [true, nil], seen
      FIBER_KEYS.each { |k| assert_nil Fiber[k], "#{k} must not outlive the turn" }
    end
  end

  def test_ingress_runner_untrusted_turn_does_not_inherit_the_callers_elevation
    with_clean_fiber do
      Fiber[:master_elevated] = true
      seen = nil
      gateway = Object.new
      gateway.define_singleton_method(:receive) { |**_kw| seen = [Fiber[:master_elevated], Fiber[:master_visitor]] }

      Master::Io::IngressRunner.run_turn(container: { gateway: }, message: "hi", elevated: false)

      assert_equal [nil, true], seen
    end
  end

  def test_ingress_runner_without_a_gateway_is_an_infrastructure_err
    result = Master::Io::IngressRunner.run_turn(container: {}, message: "hi")

    refute result.ok?
    assert_equal :infrastructure, result.category
  end

  # --- Clean -------------------------------------------------------------------

  def test_clean_script_exists_where_the_tool_looks
    assert File.file?(Master::Io::Clean::SCRIPT), "Clean shells #{Master::Io::Clean::SCRIPT}"
  end

  def test_clean_run_bounded_kills_a_child_that_overruns
    with_root do |root|
      tool = Master::Io::Clean.new(root:, governor: allow, timeout_s: 0.3)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      out, err, status = tool.send(:run_bounded, "zsh", "-c", "sleep 30")

      assert_nil status, "a timed-out child reports a nil status"
      assert_nil out
      assert_nil err
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
    end
  end

  def test_clean_refuses_a_missing_path_and_honours_the_governor
    with_root do |root|
      missing = Master::Io::Clean.new(root:, governor: allow).call(path: "nope")
      refute missing.ok?
      assert_match(/path not found/, missing.message)

      denied = Master::Io::Clean.new(root:, governor: deny).call
      refute denied.ok?
      assert_equal "denied", denied.message
    end
  end

  # --- Tree --------------------------------------------------------------------

  def test_tree_lists_the_path_it_was_given_rather_than_the_root
    with_root do |root|
      FileUtils.mkdir_p(File.join(root, "sub"))
      target = nil
      ok = Struct.new(:success?).new(true)
      capture = ->(*args) { target = args.last; ["one\n\ntwo\n", "", ok] }

      result = Master::Io::Exec.stub(:capture3, capture) do
        Master::Io::Tree.new(root:).call(path: "sub")
      end

      assert result.ok?, result.to_s
      assert_equal File.join(root, "sub"), target
      assert_equal "one\ntwo", result.value!
    end
  end

  def test_tree_refuses_a_path_outside_the_root
    with_root do |root|
      result = Master::Io::Tree.new(root:).call(path: "../..")

      refute result.ok?
      assert_match(/escapes project root/, result.message)
    end
  end

  def test_tree_script_exists_where_the_tool_looks
    assert File.file?(Master::Io::Tree::SCRIPT), "Tree shells #{Master::Io::Tree::SCRIPT}"
  end

  # --- SymbolLookup ------------------------------------------------------------

  FakeIndex = Struct.new(:built, :hits) do
    def built? = built
    def query(_name) = hits
  end

  def test_symbol_lookup_waits_for_the_index
    result = Master::Io::SymbolLookup.new(code_index: FakeIndex.new(false, [])).call(name: "X")

    refute result.ok?
    assert_match(/not built/, result.message)
  end

  def test_symbol_lookup_formats_definition_parent_and_callers
    hits = [
      { fqn: "Master::A", type: :class, file: "lib/a.rb", line: 3, parent: "Base", used_in: ["lib/b.rb:9"] },
      { fqn: "Master::C", type: :module, file: "lib/c.rb", line: 1, parent: "Object", used_in: [] },
    ]
    result = Master::Io::SymbolLookup.new(code_index: FakeIndex.new(true, hits)).call(name: "A")

    assert_equal <<~TEXT.chomp, result.value!
      Master::A (class)
        defined: lib/a.rb:3
        parent: Base
        used in:
          lib/b.rb:9

      Master::C (module)
        defined: lib/c.rb:1
        used in: (no cross-file references found)
    TEXT
  end

  def test_symbol_lookup_passes_an_index_error_through_as_err
    result = Master::Io::SymbolLookup.new(code_index: FakeIndex.new(true, { error: "bad pattern" })).call(name: "(")

    refute result.ok?
    assert_equal "symbol_lookup: bad pattern", result.message
  end

  # --- FeedbackRecord ----------------------------------------------------------

  class Learnings
    attr_reader :events

    def record_event(**event) = (@events ||= []) << event
  end

  def test_feedback_record_records_a_valid_event
    learnings = Learnings.new
    result = Master::Io::FeedbackRecord.new(learnings:).call(event_type: "tool_failure", dimension: "shell", value: "2")

    assert_equal "recorded: tool_failure / shell", result.value!
    assert_equal [{ event_type: "tool_failure", dimension: "shell", value: 2.0, metadata: nil }], learnings.events
  end

  def test_feedback_record_rejects_unknown_events_and_blank_dimensions
    learnings = Learnings.new
    tool = Master::Io::FeedbackRecord.new(learnings:)

    refute tool.call(event_type: "made_up", dimension: "x").ok?
    refute tool.call(event_type: "tool_success", dimension: "  ").ok?
    assert_nil learnings.events
  end

  def with_env(key, value)
    saved = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    saved.nil? ? ENV.delete(key) : ENV[key] = saved
  end

  # --- WebChat -----------------------------------------------------------------

  class FakeNode
    def initialize(text) = @text = text
    def text = @text
    def inner_html = "<p>#{@text}</p>"
    def focus = self
    def type(text, _key) = (@typed = text) && self
    def typed = @typed
  end

  class FakePage
    attr_reader :visited, :input

    def initialize(input:, reply:)
      @input = input
      @reply = reply
      @network = Object.new.tap { |n| n.define_singleton_method(:wait_for_idle) { |**| true } }
    end

    def network = @network
    def go_to(url) = @visited = url
    def at_css(css) = css.include?("textarea") || css.include?("prompt") ? @input : @reply
  end

  def test_web_chat_refuses_to_start_a_browser_when_disabled
    with_env("MASTER_WEB_CHAT", nil) do
      with_env("MASTER_KEYLESS", nil) do
        Master.stub(:keyless_llm_enabled?, false) do
          chat = Master::Io::WebChat.new(provider: "chatgpt")
          chat.define_singleton_method(:with_browser) { flunk "disabled chat must not launch a browser" }

          assert_raises(Master::Io::WebChat::DisabledError) { chat.ask(prompt: "hi") }
        end
      end
    end
  end

  def test_web_chat_names_an_unknown_provider
    error = assert_raises(Master::Io::WebChat::ProviderError) { Master::Io::WebChat.new(provider: "nope") }
    assert_match(/unknown web chat provider: nope/, error.message)
  end

  def test_web_chat_types_the_prompt_and_reads_a_settled_reply
    input = FakeNode.new("")
    page = FakePage.new(input:, reply: FakeNode.new("the answer"))
    chat = Master::Io::WebChat.new(provider: "chatgpt")

    reply = chat.send(:converse, page, "system\n\nhi")

    assert_equal "the answer", reply
    assert_equal "https://chatgpt.com/", page.visited
    assert_equal "system\n\nhi", input.typed
  end

  def test_web_chat_without_an_input_field_says_login_is_required
    page = FakePage.new(input: nil, reply: nil)
    chat = Master::Io::WebChat.new(provider: "chatgpt")

    error = assert_raises(Master::Io::WebChat::ProviderError) { chat.send(:converse, page, "hi") }
    assert_match(/input not found/, error.message)
  end

  # --- BedrockStub -------------------------------------------------------------

  # configure_providers! requires the stub before ruby_llm so Zeitwerk never
  # loads bedrock/auth.rb, which requires openssl. A fresh process, because in
  # this one another test may already have loaded ruby_llm in either order.
  # Without the stub the same script loads the gem's bedrock/auth.rb.
  def test_the_bedrock_stub_keeps_ruby_llm_from_loading_bedrock_auth
    script = <<~RUBY
      require #{File.expand_path('../lib/io/bedrock_stub', __dir__).inspect}
      require "ruby_llm"
      RubyLLM::Providers::Bedrock.slug
      puts $LOADED_FEATURES.grep(%r{providers/bedrock/auth}).size
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", script)

    assert status.success?, err
    assert_equal "0", out.strip
  end
end
