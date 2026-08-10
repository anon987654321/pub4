# frozen_string_literal: true

require "minitest/autorun"
require "set"

# brgen is one site. Its verticals are mountable engines, and each one owns a
# stylesheet, which is exactly the seam a typeface escapes through — nothing
# stopped an engine declaring its own.
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

  # Every brgen stylesheet, host app and engines alike.
  def brgen_stylesheets
    @brgen_stylesheets ||= (
      Dir.glob(File.join(ROOT, "brgen/app/assets/stylesheets/**/*.scss")) +
      Dir.glob(File.join(ROOT, "brgen/engines/*/app/assets/stylesheets/**/*.scss"))
    ).reject { |f| f.match?(%r{/(vendor|node_modules|public|builds)/}) }.sort
  end

  def source_without_comments(path)
    File.read(path).gsub(%r{/\*.*?\*/}m, "").gsub(%r{^\s*//.*$}, "")
  end

  # _root.scss is where brgen names its typeface; nowhere else may.
  FONT_OWNER = "brgen/app/assets/stylesheets/_root.scss"

  def test_the_scan_reaches_the_engines
    refute_empty brgen_stylesheets
    assert brgen_stylesheets.any? { |f| f.include?("/engines/") },
           "engine stylesheets missing — the blind spot that hid 57 views when the verticals moved"
  end

  def test_only_root_declares_the_typeface
    offenders = brgen_stylesheets.filter_map do |path|
      rel = path.delete_prefix("#{ROOT}/")
      next if rel == FONT_OWNER

      lines = source_without_comments(path).lines.each_with_index.select do |line, _|
        line.match?(/^\s*--font:\s/)
      end
      next if lines.empty?

      "#{rel}:#{lines.first[1] + 1} — #{lines.first[0].strip}"
    end

    assert_empty offenders, <<~MSG.strip
      a brgen surface declares its own typeface:

        #{offenders.join("\n  ")}

      brgen is one site and names its face once, in #{FONT_OWNER}. A vertical that
      redeclares --font changes the font as the reader moves between subapps.
    MSG
  end

  # A hand-written font stack is the same fork wearing different clothes: it is
  # how "SF Pro Display" and a chain ending in `Inter, sans-serif` (Inter last,
  # so it never applied) both got in.
  def test_no_stylesheet_hand_writes_a_font_stack
    allowed = /var\(--font|var\(--font-mono|inherit|var\(--offer-display/
    offenders = brgen_stylesheets.flat_map do |path|
      rel = path.delete_prefix("#{ROOT}/")
      source_without_comments(path).lines.each_with_index.filter_map do |line, index|
        next unless line.match?(/^\s*font-family:\s/)
        next if line.match?(allowed)
        # @font-face blocks legitimately name the family they are defining.
        next if rel.include?("_fonts")

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
end
