# frozen_string_literal: true

require "minitest/autorun"
require "set"
require_relative "../../MASTER/tools/design/scss_rules"

# brgen is one site. Its verticals are mountable engines, and each one's styles
# are a body.vertical-<name> scope in brgen's stylesheet, which is exactly the
# seam a typeface escapes through — nothing stopped a vertical declaring its own.
#
# Measured 2026-08-10, the font changed as you moved between subapps: Inter on
# dating and maps, "SF Pro Display" on playlist (a face that appeared in one line
# of the whole repo, was never @font-face'd and is not vendored, so off Apple it
# silently fell through to a system stack), and Arial on the feed and the
# commerce verticals, inherited from the BRGEN_OLD palette mixins. Playlist had
# also forked the type scale (--font-size-base/large/small) and the spacing scale
# (--space-xs/sm/md/lg) in parallel to the shared --text-* and --space-N, and the
# browse verticals had three different content widths with no token naming any of
# them.
#
# Two structural causes worth stating, because both are invisible in review:
#
#   A palette mixin carried the typeface. dark-tokens set --font alongside the
#   colours, so body.vertical-maps — which pins dark so the basemap and the
#   shared widgets agree — reset the face as a side effect of setting colours.
#
#   An @include emits at the point of inclusion, so brgen-old-dark-tokens'
#   `--font: Arial` outranked anything :root said before it. The app's own
#   typeface lost to a mixin it called.
class VerticalConsistencyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # Every brgen stylesheet: the host's application.scss, and any stylesheet an
  # engine grows of its own.
  def brgen_stylesheets
    @brgen_stylesheets ||= (
      Dir.glob(File.join(ROOT, "brgen/app/assets/stylesheets/**/*.scss")) +
      Dir.glob(File.join(ROOT, "brgen/engines/*/app/assets/stylesheets/**/*.scss"))
    ).reject { |f| f.match?(%r{/(vendor|node_modules|public|builds)/}) }.sort
  end

  # Newlines kept, so a line number reported from here is the file's own.
  def source_without_comments(path)
    File.read(path).gsub(%r{/\*.*?\*/}m) { |comment| comment.gsub(/[^\n]/, " ") }.gsub(%r{^[ \t]*//.*$}, "")
  end

  def brgen_rules
    @brgen_rules ||= brgen_stylesheets.flat_map do |path|
      Operator::ScssRules.rules(File.read(path)).map { |rule| [path.delete_prefix("#{ROOT}/"), rule] }
    end
  end

  # The blind spot that hid 57 views when the verticals moved, stated for the
  # styles: every engine that exists is a vertical scope the scan reads.
  def test_the_scan_reaches_the_engines
    engines = Dir.glob(File.join(ROOT, "brgen/engines/*")).map { |dir| File.basename(dir) }

    refute_empty brgen_stylesheets
    refute_empty engines, "brgen has no engines — this test is measuring nothing"
    engines.each do |engine|
      assert brgen_rules.any? { |_, rule| rule.full_selectors.any? { |selector| selector.include?("body.vertical-#{engine}") } },
             "no brgen rule styles body.vertical-#{engine}, so the #{engine} vertical is outside every check here"
    end
  end

  # brgen names its typeface once, on its :root theme; no other rule may.
  def test_only_root_declares_the_typeface
    offenders = brgen_rules.filter_map do |rel, rule|
      next unless rule.declares?(/(?<![\w-])--font\s*:/)
      next if rule.selector.start_with?(":root")

      "#{rel}:#{rule.line} — #{rule.selector}"
    end

    assert_empty offenders, <<~MSG.strip
      a brgen surface declares its own typeface:

        #{offenders.join("\n  ")}

      brgen is one site and names its face once, on its :root theme. A vertical
      that redeclares --font changes the font as the reader moves between subapps.
    MSG
  end

  # A hand-written font stack is the same fork wearing different clothes: it is
  # how "SF Pro Display" and a chain ending in `Inter, sans-serif` (Inter last,
  # so it never applied) both got in.
  def test_no_stylesheet_hand_writes_a_font_stack
    allowed = /var\(--font|var\(--font-mono|inherit|var\(--offer-display/
    offenders = brgen_stylesheets.flat_map do |path|
      rel = path.delete_prefix("#{ROOT}/")
      # @font-face blocks legitimately name the family they are defining.
      faces = brgen_rules.select { |sheet, rule| sheet == rel && rule.selector == "@font-face" }
                         .map { |_, rule| rule.line..rule.end_line }
      source_without_comments(path).lines.each_with_index.filter_map do |line, index|
        next unless line.match?(/^\s*font-family:\s/)
        next if line.match?(allowed)
        next if faces.any? { |face| face.cover?(index + 1) }

        "#{rel}:#{index + 1} — #{line.strip}"
      end
    end

    assert_empty offenders, <<~MSG.strip
      font-family written out by hand instead of using the token:

        #{offenders.join("\n  ")}

      Use var(--font) (or var(--font-mono)). A literal stack cannot follow the
      app's typeface, and one of these had Inter in last place, where it could
      never apply.
    MSG
  end

  # The shared scales are --text-* and --space-N. A vertical inventing
  # --font-size-large or --space-md gives the same element two sizes depending on
  # which subapp renders it.
  FORKED_SCALES = /^\s*--(font-size-(base|large|small|xs|sm|md|lg|xl)|space-(xs|sm|md|lg|xl)|border-radius):/

  def test_no_vertical_forks_the_type_or_spacing_scale
    offenders = brgen_stylesheets.flat_map do |path|
      rel = path.delete_prefix("#{ROOT}/")
      source_without_comments(path).lines.each_with_index.filter_map do |line, index|
        "#{rel}:#{index + 1} — #{line.strip}" if line.match?(FORKED_SCALES)
      end
    end

    assert_empty offenders, <<~MSG.strip
      a vertical declares its own type or spacing scale:

        #{offenders.join("\n  ")}

      The shared vocabulary is --text-xs..--text-2xl and --space-1..--space-16,
      in shared/app/assets/stylesheets/_tokens.scss. A parallel scale under a
      different name is how playlist ended up spacing and sizing unlike every
      other surface.
    MSG
  end

  # Verticals whose main column is a reading measure rather than a browse grid.
  # A thread and a track listing want a narrow column; a catalogue wants the
  # page. Operator decision 2026-08-10 kept these as they are.
  READING_COLUMNS = %w[messenger playlist].freeze

  def test_browse_verticals_share_one_content_width
    widths = {}
    brgen_stylesheets.each do |path|
      src = source_without_comments(path)
      src.scan(/body\.vertical-([a-z]+)\s+main\s*\{([^}]*)\}/m) do |vertical, body|
        found = body[/max-width:\s*([^;]+)/, 1]
        widths[vertical] = found.strip if found
      end
    end

    widths.reject! { |vertical, _| READING_COLUMNS.include?(vertical) }
    hardcoded = widths.reject { |_, value| value.include?("var(--container-max)") || value == "100%" }
    assert_empty hardcoded, <<~MSG.strip
      these verticals hardcode their page width instead of using --container-max:

        #{hardcoded.map { |k, v| "#{k}: #{v}" }.join("\n  ")}

      marketplace, takeaway and tv had 1280/1280/1100 with nothing naming the
      number, so the same browse grid changed width between subapps.
    MSG
  end

  # brgen's verticals are mountable engines, so their views render inside brgen
  # and live outside brgen/app. A gate scanning brgen/app/views saw none of the
  # 71 vertical pages, and the sub-apps drifted behind a green gate. The answer
  # was six engine directories written out by hand, which is correct until the
  # seventh engine — the same blind spot, deferred. UserFlowGate reads them off
  # disk now, and this holds that every engine that exists is covered.
  def test_the_view_contract_covers_every_engine
    require_relative "../../MASTER/gates/lib/live/user_flow"
    on_disk = Dir.glob(File.join(ROOT, "brgen/engines/*/app/views"))
                 .map { |path| path.sub("#{ROOT}/", "") }

    refute_empty on_disk, "brgen has no engine views — this test is measuring nothing"
    assert_empty on_disk - Deploy::UserFlowGate::VIEW_PATHS,
                 "an engine's views are outside the gate's paths, which is how 71 pages went unscanned"
    assert_includes Deploy::UserFlowGate::VIEW_PATHS, "amber/app/views"
  end
end
