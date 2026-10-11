# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ai/orientation"
require_relative "../lib/fix/wishlist"
require "tmpdir"
require "json"

class TestFixWishlistPersonas < Minitest::Test
  Personas = Master::Fix::Wishlist::Personas

  # Answers by the persona named in the prompt, so each lens gets its own reply.
  class LensAgent
    attr_reader :prompts

    def initialize(replies) = (@replies = replies; @prompts = [])

    def ask(prompt)
      @prompts << prompt
      @replies.find { |name, _| prompt.include?("You are the #{name} ") }&.last.to_s
    end
  end

  def setup
    @root = Dir.mktmpdir("wishpersonas_")
    FileUtils.mkdir_p(File.join(@root, "lib"))
    File.write(File.join(@root, "lib", "sample.rb"), "module Sample\nend\n")
  end

  def teardown = FileUtils.rm_rf(@root)

  def wish(id, title: "Title #{id}", anchor: "lib/sample.rb:1")
    "- id: #{id}\n  title: #{title}\n  rationale: r\n  anchor: #{anchor}\n  change: c #{id}\n  effort: cheap\n" \
      "  reversibility: reversible\n  implementation: next_fix\n  evidence: e\n  proof:\n    - ruby syntax"
  end

  def ledger = JSON.parse(File.read(File.join(@root, ".master", "fix_wishlist.json")))

  def test_each_persona_gets_its_own_prompt_and_wishes_are_attributed
    agent = LensAgent.new(
      "Security" => wish("shared_fix", title: "Harden the input"),
      "Maintainer" => wish("shared_fix", title: "Harden the input") + "\n" + wish("only_maint", title: "Rename things"),
      "Typographer" => wish("only_type", title: "Tighten measure"),
    )
    Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r1")

    assert_equal 4, agent.prompts.size
    assert_equal 4, agent.prompts.map { |p| p[/You are the (.+?) on the/, 1] }.uniq.size
    rows = ledger.fetch("proposals")
    assert_equal 2, ledger.fetch("schema")
    shared = rows.find { |r| r["id"] == "shared_fix" }
    assert_equal %w[Maintainer Security], shared.fetch("proposed_by")
    assert_equal 2, shared.fetch("weight")
    assert_equal "shared_fix", rows.first.fetch("id"), "the wish several personas raised leads the ledger"
    assert_equal ["Maintainer"], rows.find { |r| r["id"] == "only_maint" }.fetch("proposed_by")
    assert_equal ["ruby syntax"], shared.fetch("proof")
  end

  def test_a_later_run_adds_names_to_an_open_wish_instead_of_duplicating_it
    first = LensAgent.new("Security" => wish("dup", title: "Same wish"))
    Master::Fix::Wishlist.new(root: @root, agent: first).call(state: "done", target: @root, run_id: "r1")
    second = LensAgent.new("Maintainer" => wish("dup", title: "Same wish"), "Typographer" => wish("dup", title: "Same wish"))
    Master::Fix::Wishlist.new(root: @root, agent: second).call(state: "done", target: @root, run_id: "r2")

    rows = ledger.fetch("proposals")
    assert_equal 1, rows.size
    assert_equal %w[Maintainer Security Typographer], rows.first.fetch("proposed_by")
    assert_equal 3, rows.first.fetch("weight")
  end

  def test_no_persona_answer_falls_back_to_the_single_prompt
    calls = []
    agent = Object.new
    agent.define_singleton_method(:ask) do |prompt|
      calls << prompt
      prompt.include?("You are the ") ? "" : "- id: solo\n  title: Solo\n  rationale: r\n  anchor: lib/sample.rb:1\n  change: c\n  evidence: e\n"
    end
    Master::Fix::Wishlist.new(root: @root, agent:).call(state: "done", target: @root, run_id: "r1")

    assert_equal ["solo"], ledger.fetch("proposals").map { |r| r["id"] }
  end

  def test_schema_one_ledger_migrates_on_read
    FileUtils.mkdir_p(File.join(@root, ".master"))
    File.write(File.join(@root, ".master", "fix_wishlist.json"),
               JSON.generate("schema" => 1, "proposals" => [{ "uid" => "a", "status" => "queued" }]))
    wishlist = Master::Fix::Wishlist.new(root: @root, agent: nil)
    row = wishlist.send(:load_ledger)

    assert_equal 2, row["schema"]
    assert_equal ["shared"], row["proposals"].first["proposed_by"]
    assert_equal 1, row["proposals"].first["weight"]
  end

  def test_order_puts_heavier_wishes_first_and_is_stable
    rows = [{ "uid" => "a", "weight" => 1 }, { "uid" => "b", "weight" => 3 }, { "uid" => "c" }]

    assert_equal %w[b a c], Personas.order(rows).map { |r| r["uid"] }
  end

  def test_env_selects_personas
    names = Personas.voices("MASTER_FIX_WISH_PERSONAS" => "Reliability,User Advocate").map(&:name)

    assert_equal ["Reliability", "User Advocate"], names
  end
end
