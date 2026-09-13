# frozen_string_literal: true

# brgen's verticals are mountable engines, and each one is meant to lift out on
# its own: it depends on the host and on pub4-shared, never on a sibling. A
# constant from another engine inside app/ breaks that silently — both engines
# load in brgen, so nothing fails until one is mounted without the other.
#
# Source-text assertions, under bare ruby with no app bundle.

require "minitest/autorun"

class CrossEngineReferenceTest < Minitest::Test
  ROOT = File.expand_path("../brgen/engines", __dir__)

  # file relative to engines/ => { constant => reason }. A row here is a
  # decision, not a baseline: each carries the argument for crossing.
  EXEMPT = {
    "maps/app/controllers/maps/home_controller.rb" => {
      "Takeaway" => "the courier layer shows the viewer's own takeaway courier on the city map; " \
                    "the map is the host's surface for every located thing, and an order out for " \
                    "delivery has no other place to be seen moving"
    }
  }.freeze

  def engine_modules
    @engine_modules ||= Dir.glob(File.join(ROOT, "*/lib/*/engine.rb")).to_h do |path|
      [ path.delete_prefix("#{ROOT}/").split("/").first, File.read(path)[/^module (\w+)/, 1] ]
    end
  end

  # Comments are dropped so a sentence naming another vertical is not a
  # dependency on it. Only whole-line Ruby comments and ERB comment tags: a
  # trailing comment that names a constant still reads as code, which fails
  # loudly rather than hiding anything.
  def code_of(path, source)
    if path.end_with?(".erb")
      source.gsub(/<%#.*?%>/m) { |comment| "\n" * comment.count("\n") }
    else
      source.lines.map { |line| line.lstrip.start_with?("#") ? "\n" : line }.join
    end
  end

  def references(path, source, own_module)
    others = engine_modules.values - [ own_module ]
    code_of(path, source).lines.each_with_index.flat_map do |line, index|
      others.filter_map { |other| [ other, index + 1 ] if line.match?(/(?<![\w:])(?:::)?#{other}::[A-Z]/) }
    end
  end

  def crossings
    engine_modules.flat_map do |engine, own_module|
      Dir.glob(File.join(ROOT, engine, "app/**/*.{rb,erb}")).sort.flat_map do |path|
        relative = path.delete_prefix("#{ROOT}/")
        references(relative, File.read(path), own_module).map { |other, line| [ relative, other, line ] }
      end
    end
  end

  def test_the_scan_found_the_engines
    assert_operator engine_modules.size, :>=, 6, "engines/*/lib/*/engine.rb matched too little — check the glob, not the tree"
    refute_includes engine_modules.values, nil
  end

  def test_no_engine_reaches_into_a_sibling
    unexempted = crossings.reject { |file, other, _| EXEMPT.dig(file, other) }
    assert_empty unexempted.map { |file, other, line| "#{file}:#{line} references #{other}::" },
                 "an engine's app/ names a sibling engine's constant. Move the shared piece into the host " \
                 "or pub4-shared, or add an EXEMPT row that argues for the crossing"
  end

  def test_every_exemption_is_still_needed
    found = crossings.map { |file, other, _| [ file, other ] }.uniq
    stale = EXEMPT.flat_map { |file, constants| constants.keys.map { |other| [ file, other ] } } - found
    assert_empty stale, "an EXEMPT row no longer matches any reference — delete it"
  end

  def test_the_detector_flags_a_sibling_constant_and_spares_comments
    own = engine_modules.fetch("dating")
    assert_equal [ [ "Takeaway", 1 ] ], references("x.rb", "Takeaway::Order.first\n", own)
    assert_empty references("x.rb", "# Takeaway::Order is mentioned\n", own)
    assert_empty references("x.html.erb", "<%# Takeaway::Order %>\n", own)
    assert_empty references("x.rb", "Dating::Profile.first\n", own)
  end
end
