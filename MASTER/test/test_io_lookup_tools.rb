# frozen_string_literal: true

require_relative "test_helper"

# SearchKnowledge and SymbolLookup are the two read-only lookups the agent can
# call, and IngressRunner is how a webhook, bridge or cron message becomes a
# turn. The lookups must stay inside what they index; the runner must never
# leave a turn's authority behind on the fiber.
class TestIoLookupTools < Minitest::Test
  def setup
    @root = File.realpath(Dir.mktmpdir("lookup_"))
    FileUtils.mkdir_p(File.join(@root, "knowledge", "openbsd"))
    FileUtils.mkdir_p(File.join(@root, "knowledge_private"))
    File.write(File.join(@root, "knowledge", "openbsd", "relayd.md"), "one\ntwo\nrelayd header limit\nfour\nfive\nsix\n")
    File.write(File.join(@root, "knowledge_private", "secret.md"), "relayd secret\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def search(**args) = Master::Io::SearchKnowledge.new(root: @root).call(**args)

  def test_matches_come_with_two_lines_of_context_and_a_location
    text = search(query: "RELAYD", topic: "openbsd").value!

    assert_includes text, "(1 matches)"
    assert_includes text, "### openbsd/relayd.md:3\n1: one\n2: two\n3: relayd header limit\n4: four\n5: five\n"
  end

  def test_a_topic_cannot_climb_out_of_knowledge
    result = search(query: "relayd", topic: "../knowledge_private")

    assert result.err?
    assert_match(/unknown topic/, result.message)
  end

  def test_an_invalid_regexp_is_searched_literally
    File.write(File.join(@root, "knowledge", "openbsd", "brackets.md"), "a [b\n")

    assert_includes search(query: "[b").value!, "brackets.md:1"
  end

  def test_topics_are_the_visible_directories
    assert_equal ["openbsd"], Master::Io::SearchKnowledge.new(root: @root).available_topics
  end

  Index = Struct.new(:built, :answer) do
    def built? = built
    def query(_name) = answer
  end

  def test_symbol_lookup_formats_definitions_and_references
    hit = { fqn: "Master::Io::Clean", type: :class, file: "lib/io/clean.rb", line: 9, parent: "Object", used_in: [] }
    other = hit.merge(fqn: "Master::X", parent: "Base", used_in: ["lib/a.rb:3"])
    text = Master::Io::SymbolLookup.new(code_index: Index.new(true, [hit, other])).call(name: "Clean").value!

    assert_equal "Master::Io::Clean (class)\n  defined: lib/io/clean.rb:9\n  used in: (no cross-file references found)" \
                 "\n\nMaster::X (class)\n  defined: lib/io/clean.rb:9\n  parent: Base\n  used in:\n    lib/a.rb:3", text
  end

  def test_symbol_lookup_refuses_before_the_index_is_built_and_passes_index_errors_on
    refute Master::Io::SymbolLookup.new(code_index: Index.new(false, [])).call(name: "X").ok?
    assert_equal "symbol_lookup: bad name",
                 Master::Io::SymbolLookup.new(code_index: Index.new(true, { error: "bad name" })).call(name: "?").message
  end

  Gateway = Struct.new(:seen) do
    def receive(channel:, message:, metadata:)
      seen << [channel, message, metadata, Fiber[:master_elevated], Fiber[:master_visitor]]
      Master::Result.ok("done")
    end
  end

  def test_ingress_marks_the_turn_and_clears_every_flag_after_it
    gateway = Gateway.new([])
    Fiber[:master_paired] = true
    Master::Io::IngressRunner.run_turn(container: { gateway: }, message: :hi, metadata: { from: "cron" })
    Master::Io::IngressRunner.run_turn(container: { gateway: }, message: "op", elevated: true)

    assert_equal [[:api, "hi", { from: "cron" }, nil, true], [:api, "op", {}, true, nil]], gateway.seen
    assert_nil Fiber[:master_elevated]
    assert_nil Fiber[:master_visitor]
    assert_nil Fiber[:master_paired]
  end

  def test_ingress_without_a_gateway_is_an_infrastructure_error
    assert_equal :infrastructure, Master::Io::IngressRunner.run_turn(container: {}, message: "x").category
  end
end
