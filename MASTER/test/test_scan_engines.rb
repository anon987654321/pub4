# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/scanner"

# The scanner's supporting engines, first tested here: SourceMasking's
# length-preserving blanks (a finding's line and column must still point at the
# real source), PathFilter's refusal list, Transport's changed-file selection and
# thread pool, ProgressReporter's tallies, and the DatalogEngine fact base
# FastStage queries.
class TestScanEngines < Minitest::Test
  class Masker
    include Master::Review::Scan::SourceMasking
  end

  SAMPLE = <<~SRC
    # a comment line
    x = y / z  # trailing stays
    pattern = /secret word/i
    <img src="<%= deal.image_url %>"
         alt="<%= deal.title %>">
    <%# a note about #fff %>
    .a { color: var(--ink, #123456); /* pinned #202020 */ }
    @media (prefers-reduced-motion: reduce) { .b { animation: none; } }
    run(<<~JS)
      f && f.primerFired
    JS
    fires: "bad shape"
  SRC

  # The flattening masks move a wrapped tag onto its opening line, so they keep
  # line count but not length; every other mask keeps both.
  FLATTENING = %i[with_tags_flattened tag_source control_source].freeze
  MASKS = %i[without_comment_lines without_rule_fixtures without_regex_literals without_erb_tags
             without_labelled_controls without_block_comments
             without_var_fallbacks without_erb_comments without_mask_gradients declaration_values_only
             without_override_media without_foreign_heredocs with_erb_output_as_text].freeze

  def test_every_mask_keeps_line_count_and_the_blanking_ones_keep_length
    masker = Masker.new
    (MASKS + FLATTENING).each do |mask|
      out = masker.send(mask, SAMPLE)

      assert_equal SAMPLE.count("\n"), out.count("\n"), "#{mask} moved a line"
      assert_equal SAMPLE.length, out.length, "#{mask} changed the length" if MASKS.include?(mask)
    end
  end

  def test_masks_blank_what_they_name_and_nothing_else
    m = Masker.new

    refute_includes m.without_comment_lines(SAMPLE), "a comment line"
    assert_includes m.without_comment_lines(SAMPLE), "# trailing stays"
    refute_includes m.without_regex_literals(SAMPLE), "secret word"
    assert_includes m.without_regex_literals(SAMPLE), "y / z"
    refute_includes m.without_var_fallbacks(SAMPLE), "#123456"
    refute_includes m.without_block_comments(SAMPLE), "#202020"
    refute_includes m.without_override_media(SAMPLE), "animation"
    refute_includes m.without_foreign_heredocs(SAMPLE), "primerFired"
    refute_includes m.without_rule_fixtures(SAMPLE), "bad shape"
    assert_match(/<img src="\s+"\s+alt=/, m.tag_source(SAMPLE).lines[3]) # source-assertion: ok — the scanner's rendered tag, not a source file
  end

  def test_a_button_named_by_its_text_is_not_nameless
    html = "<button><%= t(\"save\") %></button>\n<button class=\"x\"></button>\n<input type=\"hidden\">\n<input>\n"

    assert_equal [2, 4], Masker.new.nameless_control_lines(html)
  end

  def test_dark_background_is_read_from_the_enclosing_block
    css = ".a {\n  background: #111;\n  color: #eee;\n}\n.b {\n  background: #fafafa;\n  color: #333;\n}\n"

    assert Masker.new.dark_background_near?(css, 3)
    refute Masker.new.dark_background_near?(css, 7)
  end

  PF = Master::Review::Scan::PathFilter

  def test_path_filter_skips_generated_and_vendored_paths_from_either_root
    root = "/repo"

    assert PF.skip_path?("/repo/MASTER/web/public/face.runtime.js", root:)
    assert PF.skip_path?("/repo/RAILS/brgen/db/schema.rb", root:)
    assert PF.skip_path?("/repo/RAILS/brgen/app/assets/builds/application.css", root:)
    assert PF.skip_path?("/repo/RAILS/shared/public/swiper-bundle.min.css", root:)
    assert PF.skip_path?("/repo/MASTER/tools/dilla/scratch/venv/x.py", root:)
    refute PF.skip_path?("/repo/MASTER/lib/review/scan/scanner.rb", root:)
    refute PF.skip_path?("/repo/RAILS/brgen/db/seeds.rb", root:)
  end

  class Host
    include Master::Review::Scan::Transport

    def self.skip_path?(path, root:) = Master::Review::Scan::PathFilter.skip_path?(path, root:)

    def initialize(bus = nil) = @bus = bus
    public :scan_since_paths, :parallel_map, :under_path?, :git_capture
  end

  def test_scan_since_keeps_existing_scannable_files_under_the_scan_root
    repo = File.realpath(Dir.mktmpdir("transport_"))
    %w[app/a.rb app/b.png other/c.rb MASTER/lib/d.rb app/vendor/e.rb].each do |rel|
      FileUtils.mkdir_p(File.dirname(File.join(repo, rel)))
      File.write(File.join(repo, rel), "")
    end
    changed = %w[app/a.rb app/b.png other/c.rb MASTER/lib/d.rb app/vendor/e.rb app/gone.rb app/a.rb]

    paths = Host.new.scan_since_paths(changed, dir: File.join(repo, "app"), repo_root: repo)
    assert_equal %w[app/a.rb MASTER/lib/d.rb], paths.map { |p| p.delete_prefix("#{repo}/") }
  ensure
    FileUtils.rm_rf(repo)
  end

  def test_parallel_map_keeps_order_and_turns_a_raise_into_an_error_result
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |name, **payload| events << [name, payload[:index]] }
    results = Host.new(bus).parallel_map((0...12).to_a) do |item, _i|
      raise "boom" if item == 7

      item * 2
    end

    assert_equal [0, 2, 4, 6, 8, 10, 12], results.first(7)
    assert_equal [16, 18, 20, 22], results.last(4)
    assert results[7].last.err?
    assert_equal [["scanner:thread_error", 7]], events
  end

  def test_a_wedged_git_reads_as_a_failed_command
    result = Timeout.stub(:timeout, ->(*) { raise Timeout::Error }) { Host.new.git_capture("git", "status") }

    refute result.last.success?
    assert_match(/timed out/, result[1])
  end

  class Reporter
    include Master::Review::Scan::ProgressReporter

    def initialize
      @mutex = Mutex.new
      @scan_progress = { total: 3, done: 0, violations: 0, dirty_files: 0, rules: Hash.new(0) }
    end
    public :update_scan_progress_state, :checkpoint_step
  end

  def test_progress_tallies_violations_dirty_files_and_top_rules
    reporter = Reporter.new
    reporter.update_scan_progress_state(2, %w[long_line magic_number])
    reporter.update_scan_progress_state(0, [])
    done, total, violations, dirty, top = reporter.update_scan_progress_state(1, %w[long_line])

    assert_equal [3, 3, 3, 2], [done, total, violations, dirty]
    assert_equal [["LONG_LINE", 2], ["MAGIC_NUMBER", 1]], top
  end

  def test_checkpoints_thin_out_as_the_walk_grows
    reporter = Reporter.new

    assert_equal [1, 5, 10, 25, 100], [10, 50, 100, 200, 1000].map { |n| reporter.checkpoint_step(n) }
  end

  def test_datalog_facts_come_from_the_ast_and_negation_is_honoured
    source = "class A\n  def go\n    work\n  rescue\n    nil\n  end\nend\n"
    engine = Master::Review::Scan::DatalogEngine.from_ruby("a.rb", source)

    assert_equal [["a.rb", 4]], engine.query(:bare_rescue).map(&:args)
    assert_equal 1, engine.query(:method_def, "a.rb", "go").size
    engine.rule(:rescue_in_class, :bare_rescue, :class_def) { |fact| "bare rescue at #{fact.args[1]}" }
    engine.rule(:never, :bare_rescue, [:not, :class_def])

    assert_equal ["bare rescue at 4"], engine.evaluate.map(&:message)
  end

  def test_unparseable_ruby_yields_an_empty_fact_base
    assert_empty Master::Review::Scan::DatalogEngine.from_ruby("a.rb", "def (").query(:call)
  end
end
