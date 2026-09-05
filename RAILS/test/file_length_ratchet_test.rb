# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

# rb_file_too_long / scss_file_too_long / view_too_long, as a ratchet rather than
# three lists — the same conclusion method_length_ratchet_test.rb reaches, for the
# same reason: a finding list is a snapshot and cannot hold a line while you work
# down it.
#
# Counted in code lines, non-blank and non-comment, matching lint:spine (which was
# re-expressed the same day), [DENSITY], and the method ratchet. Under the raw
# count these rules charged for documentation, and this tree's convention is a
# paragraph of rationale above the tricky line. Four of the recorded 24 findings
# were only ever over the limit on their comments: _brand.scss (441 raw / 379
# code), _chrome_polish.scss (405/366), amber's application layout (153/143) and
# gates/lib/live/page_simulation.rb (360/295).
#
# Generated files are excluded rather than exempted-in-place, because "split it"
# is not an available action for them: db/schema.rb is written by Rails from the
# migrations and hand-edits are overwritten on the next `db:migrate`. brgen's is
# 1,359 code lines and will never be anything else.
class FileLengthRatchetTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # kind => [glob roots, limit in code lines]
  LIMITS = { "rb" => 300, "scss" => 400, "erb" => 150 }.freeze

  # Rails writes these from the migrations; a split is undone by the next
  # db:migrate. Excluded, not allow-listed, so they never read as debt.
  GENERATED = %r{/db/schema\.rb\z}

  # file => code lines. Re-measured 2026-08-10 after code_lines learned to strip
  # block comments (see below). Lower a number when you split something; never
  # raise one, and never add a row without saying why here.
  #
  # Only the .scss and .erb numbers moved, and brgen's PWA manifest left the list
  # outright: it was never over the limit on code, only on the prose above it.
  # The .rb numbers are unchanged, which is the point of stripping per language —
  # a first pass that also treated `/*` as a Ruby comment reported four .rb files
  # as 100–290 lines shorter, all of it real code sitting between the `/*` and
  # the `*/` of a glob like `"**/*.rb"`.
  #
  # db/seeds.rb is data rather than logic — long lists of seed rows. It is on
  # the list because splitting it is possible, not because it is obviously
  # worth doing.
  #
  # plausible_content.rb left the list on 2026-08-12: it reached 512 against a
  # 344 ceiling, and the pools that made it long were data with one reader
  # each, so they moved to plausible_content/{prose,commerce}.rb and the
  # remainder is 129 lines of methods. That is what "splitting is possible"
  # looked like when something finally forced it.
  CEILINGS = {
    "brgen/lib/brgen/bergen_demo_seeder.rb" => 839,
# 746 -> 618 on 2026-08-26. The eight infinite-scroll wiring assertions are
# infinite_scroll_wiring_test.rb — one subject, and the one most likely to
# keep growing, rather than eight more entries in a bundle of forty
# unrelated deploy contracts. ROOT and the two source readers went to
# test/source_reader.rb so both files answer "where is the tree"
# the same way; copying them would have made two answers that drift, which
# is the failure ROOT's own comment records from 2026-07-10.
"brgen/test/services/deploy_backlog_test.rb" => 618,
# 522 -> 442 on 2026-08-26. Token contrast and the budget that judges it —
# check_token_contrast, judge_contrast_budget, contrast_budget — are
# design_metrics/contrast_checks.rb. One subject, and the maths it calls
# was split off the same subject at the other layer in
# gates/support/design_metrics_contrast.rb.
#
# The move broke something first, in the way this repo keeps finding: the
# budget path was `File.expand_path("../../data/css_budget.yml", __dir__)`
# and one directory deeper that resolves to gates/lib/data, which does not
# exist. No exception — a rescue logged "rules unreadable" and ran the gate
# unbudgeted, so the contrast ceiling stopped being enforced while the gate
# still printed ok. Caught by diffing the gate's whole output before and
# after, which is now the standard for a split in this file.
"gates/lib/research/design_metrics.rb" => 442,
# 498 -> 449 on 2026-08-26. check_contrast, apca_note and check_apca are
# rendered_geometry/contrast_checks.rb — the one subject in this gate that
# is colour rather than geometry, and the rendered counterpart to the
# source-side checks split out of design_metrics the same day.
#
# Verified by diffing the gate's whole output, and that diff is worth
# recording because it was not empty: subpixel and type_scale findings
# moved by a component or two. Running it a third time with no edit between
# moved them again, so those two checks are non-deterministic run to run
# and the delta was not the split. The 108 contrast and apca findings —
# the ones this file is actually responsible for — were byte-identical
# across all three runs.
"gates/lib/rendered/rendered_geometry.rb" => 449, # type checks live in geometry_type.rb
    # +6 in cf6e56a52 — an error template is not a route, so the manifest stopped
    # being hand-edited and the inventory learned to tell the two apart.
    "gates/support/page_inventory.rb" => 440,
# 428 -> 339 on 2026-08-26. The seam was already drawn in the file: a
# `--- websocket framing ---` banner, above which every method speaks CDP
# (navigate, evaluate, press, screenshot) and below which every method
# speaks RFC 6455 and knows nothing about Chrome. The 101 lines below it
# are gates/support/cdp_framing.rb, included back in, so the methods stay
# private to CdpSession exactly as they were.
#
# Two constants had to move or be qualified: MAX_FRAME_BYTES went with its
# only reader, and Error/Desync are now CdpSession::. Constant lookup is
# lexical and an included module does not see the includer's constants —
# which surfaced as the frame reader raising NameError, reported by the
# runner as a gate that errored and blocked nothing. Verified by running
# viewport_spill and occlusion against live apps with GATE_STRICT_ERRORS=1;
# the desync-recovery path fires in that run, so the extracted code is
# exercised rather than merely loaded.
    # 436 -> 406 on 2026-08-26. The dependency graph and the wordmark went
    # to _port_graph.scss. Left the list 2026-09-05: under the 400 scss
    # limit, so a ceiling here would only re-admit it.
    #
    # Recorded 338 earlier the same day from this ratchet's own staleness
    # message, and it measures 339 now. One line, and its provenance is not
    # attributable: three sessions were writing this tree through the pass and
    # HEAD moved twice. 428 -> 339 is the number that matters and it is still
    # down by 89; recording what it measures is the honest reading rather than
    # a guess about which session added the line.
    "gates/support/cdp_session.rb" => 339,
    # +5 in 7ed6920cd — the seeds asked for a visible profile without a photo,
    # which gated every deploy.
    "brgen/db/seeds.rb" => 426,
    "gates/lib/live/user_flow.rb" => 313,
    "shared/app/assets/stylesheets/_minimal.scss" => 455,
    "shared/app/assets/stylesheets/_zen_shell.scss" => 477,
    "brgen/engines/playlist/app/views/playlist/playlists/_player.html.erb" => 155,
  }.freeze

  COMMENT_STARTS = ["#", "//", "/*", "*", "<%#"].freeze

  # Block comments are removed before the line rule runs, rather than the rule
  # skipping lines that *start* with a marker. COMMENT_STARTS catches the first
  # line of a `<%# … %>` or `/* … */` block and nothing after it, because this
  # tree writes continuation lines as plain indented prose with no leading star.
  # So a rule meant to spare documentation charged for all but its first line —
  # brgen's application layout measured 317 against a 264-line body, and the way
  # to satisfy the ratchet was to delete the paragraph explaining the CSS
  # specificity race the file exists to work around.
  #
  # css_constitution learned the same lesson the same day about px values and
  # hex colours in comments. This is that fix, extended to ERB.
  #
  # Per-language, and that is not fussiness. `/*` is a comment opener in SCSS and
  # a substring of every glob in Ruby: `Dir.glob("**/*.rb")` contains both `/*`
  # and `*/`, so a language-blind stripper deletes real code between them. It
  # measured 60 files in this tree with "unbalanced" markers, all of them Ruby
  # globs and regexes. Ruby's own block form is =begin/=end, which is what it
  # gets here.
  BLOCK_COMMENTS = {
    "scss" => [["/*", "*/"]],
    "erb" => [["<%#", "%>"], ["/*", "*/"]],
    "rb" => [],
  }.freeze

  def strip_block_comments(body, kind)
    pairs = BLOCK_COMMENTS.fetch(kind)
    return strip_ruby_block_comments(body) if pairs.empty?

    out = +""
    rest = body
    until rest.empty?
      open = pairs.filter_map { |o, _| rest.index(o) }.min
      return out << rest if open.nil?

      opener = pairs.find { |o, _| rest[open, o.length] == o }
      out << rest[0...open]
      close = rest.index(opener[1], open + opener[0].length)
      return out if close.nil?

      # Keep the newlines so the count stays a line count.
      out << ("\n" * rest[open..close].count("\n"))
      rest = rest[(close + opener[1].length)..] || ""
    end
    out
  end

  def strip_ruby_block_comments(body)
    inside = false
    body.each_line.map do |line|
      if line.start_with?("=begin")
        inside = true
      elsif line.start_with?("=end")
        inside = false
        next "\n"
      end
      inside ? "\n" : line
    end.join
  end

  def code_lines(path)
    kind = File.extname(path).delete_prefix(".")
    kind = "erb" if path.end_with?(".erb")
    strip_block_comments(File.read(path), kind).each_line.count do |line|
      stripped = line.strip
      !stripped.empty? && !stripped.start_with?(*COMMENT_STARTS)
    end
  end

  def candidates
    @candidates ||= begin
      apps = %w[shared brgen amber bsdports gates tools test lib]
      rb = apps.flat_map { |a| Dir.glob(File.join(ROOT, a, "**/*.rb")) }
      scss = %w[shared brgen amber bsdports].flat_map { |a| Dir.glob(File.join(ROOT, a, "**/*.scss")) }
      erb = %w[shared brgen amber bsdports].flat_map do |a|
        Dir.glob(File.join(ROOT, a, "app/views/**/*.erb")) +
          Dir.glob(File.join(ROOT, a, "engines/*/app/views/**/*.erb"))
      end
      { "rb" => rb, "scss" => scss, "erb" => erb }.transform_values do |paths|
        paths.reject { |p| p.match?(%r{/(vendor|node_modules|public)/|/db/migrate/}) || p.match?(GENERATED) }
             .uniq.sort
      end
    end
  end

  def oversize
    candidates.flat_map do |kind, paths|
      limit = LIMITS.fetch(kind)
      paths.filter_map do |path|
        lines = code_lines(path)
        [path.delete_prefix("#{ROOT}/"), lines] if lines > limit
      end
    end.to_h
  end

  def test_the_scan_reaches_the_tree_it_claims_to
    assert candidates.values.all? { |paths| paths.size.positive? }, "a glob returned nothing"
    assert candidates["erb"].any? { |p| p.include?("/engines/") },
           "engine views are missing, the blind spot that hid 57 of them"
  end

  def test_generated_schema_is_excluded_not_counted
    schema = File.join(ROOT, "brgen/db/schema.rb")
    skip "brgen/db/schema.rb absent" unless File.exist?(schema)

    assert_operator code_lines(schema), :>, LIMITS["rb"],
                    "if schema.rb were short this exclusion would be pointless"
    refute_includes candidates["rb"], schema,
                    "schema.rb is regenerated by db:migrate — a split is undone, so it is excluded"
  end

  def test_length_is_measured_in_code_lines_not_raw
    Dir.mktmpdir do |dir|
      path = File.join(dir, "documented.rb")
      File.write(path, (["# explanation"] * 500 + ["x = 1"] * 3).join("\n"))
      assert_equal 3, code_lines(path), "500 comment lines must not count against a 3-line file"
    end
  end

  def test_no_file_exceeds_its_ceiling
    risen = oversize.filter_map do |path, lines|
      ceiling = CEILINGS[path]
      if ceiling.nil?
        "#{path}: #{lines} code lines, over the limit and no ceiling declared"
      elsif lines > ceiling
        "#{path}: #{lines} code lines, ceiling is #{ceiling} (+#{lines - ceiling})"
      end
    end

    assert_empty risen, <<~MSG.strip
      files have grown past their ceilings:

        #{risen.join("\n  ")}

      Split the file rather than raising the number. A new entry here means a new
      long file was added, which is the thing three separate measurements of this
      backlog failed to prevent.
    MSG
  end

  # Only downward. This compared for inequality, so a file that had *grown* was
  # reported here too — under the heading "the tree is better than the ratchet
  # records", with the instruction to lower the ceiling to match. Following that
  # on a 272-line file with a 264 ceiling would have recorded the regression as
  # the new floor and closed the failure that was telling the truth about it.
  # Growth is test_no_file_exceeds_its_ceiling's to report, and only its.
  def test_ceilings_are_not_slack
    current = oversize
    slack = CEILINGS.filter_map do |path, ceiling|
      if current[path].nil?
        "#{path}: no longer over the limit — remove the row"
      elsif current[path] < ceiling
        "#{path}: now #{current[path]}, recorded #{ceiling} — lower it"
      end
    end

    assert_empty slack, <<~MSG.strip
      the tree is better than the ratchet records:

        #{slack.join("\n  ")}

      A ceiling above the real number is slack the next long file grows into
      without failing anything.
    MSG
  end
end
