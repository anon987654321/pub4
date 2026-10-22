# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fix/scanner"

# A model read of unchanged text is replayed, clean or not, so a /fix run asks the model only about what
# changed. An inconclusive read is never kept: an outage must not stand in for an answer.
class TestSemanticReplay < Minitest::Test
  Finding = Master::Review::Scan::Finding
  PATH = File.join(Master::ROOT, "lib", "semantic_replay_probe.rb")

  # A cheap finding, so the file is due a semantic read.
  class CheapLaw
    def self.reads_beyond_file? = false
    def id = "CHEAP"
    def check(_code, path:) = [Finding.build(law: "CHEAP", message: "cheap #{File.basename(path)}", line: 1)]
  end

  class ModelLaw
    attr_reader :calls

    def self.reads_beyond_file? = true

    def initialize(answer) = (@answer = answer) && (@calls = 0)
    def id = "MODEL"
    def set_agent(_agent) = nil

    def check(_code, path:)
      @calls += 1
      raise "semantic assessment INCONCLUSIVE: lane down" if @answer == :inconclusive

      [Finding.build(law: "MODEL", message: "drift in #{File.basename(path)}", line: 2)]
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @was = ENV.fetch("MASTER_SCAN_CACHE", nil)
    ENV["MASTER_SCAN_CACHE"] = "1"
  end

  def teardown
    @was.nil? ? ENV.delete("MASTER_SCAN_CACHE") : ENV["MASTER_SCAN_CACHE"] = @was
    FileUtils.remove_entry(@dir)
  end

  def scan(law, code: "x = 1\n")
    processor = Master::Fix::Scan::FileProcessor.new(cache_root: @dir)
    processor.apply_laws(code:, ast: nil, path: PATH, law_set: [CheapLaw.new, law])
  end

  def test_a_read_with_findings_is_replayed_for_unchanged_text
    law = ModelLaw.new(:drift)
    first = scan(law)
    second = scan(law)

    assert_equal 1, law.calls
    assert_equal first, second
    assert_includes second.map { |finding| finding[:law] }, "MODEL"
  end

  def test_changed_text_is_read_again
    law = ModelLaw.new(:drift)
    scan(law)
    scan(law, code: "x = 2\n")

    assert_equal 2, law.calls
  end

  def test_an_inconclusive_read_is_asked_again
    law = ModelLaw.new(:inconclusive)
    2.times { scan(law) }

    assert_equal 2, law.calls
  end
end
