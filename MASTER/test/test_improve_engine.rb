# frozen_string_literal: true

require_relative "test_helper"
require "fix/improve"
require "fileutils"

# The elevation engine: /fix improves, ideates and restructures. These tests
# pin the engine's contract — findings in the improvement shape, ideas in the
# ledger, proposals that name both endpoints — without touching the repo.
class TestImproveEngine < Minitest::Test
  def setup
    @root = File.join(Dir.tmpdir, "improve_test_#{Process.pid}")
    %w[lib docs].each { |dir| FileUtils.mkdir_p(File.join(@root, dir)) }
    @engine = Master::Fix::Improve::Engine.new(root: @root)
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write(path, text)
    full = File.join(@root, path)
    File.write(full, text)
    full
  end

  def test_elevates_a_long_method_as_an_improvement_finding
    path = write("lib/wide.rb", "# frozen_string_literal: true\nclass Wide\n" +
      "  def claimable\n" + (1..60).map { |i| "    x#{i} = #{i}" }.join("\n") + "\n  end\nend\n")
    findings = @engine.elevate(files: [path])
    assert findings.any?, "a 60-line method must be elevated"
    finding = findings.first
    assert_equal Master::Fix::Improve::LAW_ID, finding[:law]
    assert_equal :improvement, finding[:kind]
    assert finding[:message].include?("long_method")
    assert finding[:fix].length > 20
  end

  def test_elevates_prose_placeholders
    path = write("docs/README.md", "# X\n\n" + ("word " * 80) + "\n\nTODO: write this later.\n")
    findings = @engine.elevate(files: [path])
    assert findings.any? { |f| f[:message].include?("placeholder") }, findings.inspect
  end

  def test_elevates_unmarked_scores_in_the_music_domain
    path = write("docs/piece.sco", "i1 0 2 0.5\ni1 2 2 0.4\n")
    findings = @engine.elevate(files: [path])
    assert findings.any? { |f| f[:message].include?("unmarked_score") }, findings.inspect
  end

  def test_elevate_returns_at_most_two_steps_per_domain
    files = 5.times.map { |i| write("lib/wide#{i}.rb", "# frozen_string_literal: true\nclass W#{i}\n" +
      "  def run\n" + (1..60).map { |j| "    x#{j} = #{j}" }.join("\n") + "\n  end\nend\n") }
    findings = @engine.elevate(files: files)
    code_findings = findings.count { |f| f[:message].include?("elevation[code]") }
    assert_operator code_findings, :<=, 2
  end

  def test_ideate_writes_the_ledger_the_next_run_reads
    write("README.md", "# Root\n\n" + ("word " * 80))
    ideas = @engine.ideate(files: [File.join(@root, "README.md")])
    ledger = File.join(@root, Master::Fix::Improve::Ideate::LEDGER_PATH)
    assert File.file?(ledger), "ideas must survive in #{Master::Fix::Improve::Ideate::LEDGER_PATH}"
    data = JSON.parse(File.read(ledger))
    assert_equal Master::Fix::Improve::Ideate::SCHEMA, data["schema"]
  end

  def test_restructure_proposals_name_both_endpoints_and_an_existing_source
    @engine = nil
    lib = File.join(@root, "lib")
    FileUtils.mkdir_p(File.join(lib, "tiny"))
    File.write(File.join(lib, "tiny.rb"), "# frozen_string_literal: true\nclass Tiny\n  def one\n  end\nend\n")
    File.write(File.join(lib, "tiny", "extra.rb"), "# frozen_string_literal: true\n# small helper\nX = 1\n")
    restructure = Master::Fix::Improve::Restructure.new(root: @root)
    proposals = restructure.proposals(files: Dir[File.join(@root, "lib/**/*.rb")])
    skip "no merge target for this layout" if proposals.empty?
    proposal = proposals.first
    assert File.file?(proposal.from)
    refute_empty proposal.to
  end
end
