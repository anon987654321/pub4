# frozen_string_literal: true

require "set"

module Pub4
  # The other half of css_coverage_lint: a stylesheet asking for a *file* that is
  # not there.
  #
  # css_coverage_lint measures class names in both directions and never looks
  # inside a declaration, so nothing in this tree read `url()`. The audit that
  # produced it checked `image_tag` and `asset_path` — helper calls, which fail
  # loudly — and skipped the one reference form that fails silently. Propshaft
  # warns at precompile for some of them and not others, and the warning it does
  # print is unactionable noise (`shared/public/fonts` is served by the engine's
  # static middleware, not digested by the pipeline, so those files are present
  # and warned about anyway). A warning that is wrong most of the time trains
  # people to skip the one time it is right.
  #
  # Measured 2026-08-12: three of brgen's `pp-neue-montreal` weights 404 in
  # production, and had since the file was written. `font-display: optional`
  # means the page never blocks and no pixel visibly changes, which is why five
  # months of deploys and an asset audit did not surface it.
  #
  #   missing_asset — a url() whose file exists in none of the roots that serve
  #     the stylesheet. Counted, not fixed: whether the answer is to add the file
  #     or drop the reference depends on why it is missing, and for the three
  #     PP Neue Montreal weights the SCSS already answers it (licensed font,
  #     files deliberately absent, `local()` + fallback carries the surface).
  module AssetUrlLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)
    APPS = %w[amber brgen bsdports].freeze
    TREES = (APPS + %w[shared]).freeze

    # Measured 2026-08-12: 9 reported → 5 recorded, after fixing the one that was
    # a live bug.
    #
    # 9 → 5 was the work. amber's layout links `/lightgallery.css`, amber has no
    # copy of its own, so it was served `shared/public/lightgallery.css` — whose
    # icon font and spinner live at `../fonts/lg.*` and `../images/loading.gif`,
    # present in `brgen/public` and in no root amber can see. Verified against
    # production before and after: `amber.brgen.no/fonts/lg.woff2` was 404 while
    # the stylesheet asking for it was 200, so every lightbox control in amber
    # rendered as a missing glyph. Four files copied into `shared/public`, which
    # the engine's static middleware serves to all three apps.
    #
    # The 5 that remain are both deliberate:
    #
    # 3 are pp-neue-montreal-latin-{400,600,700}-normal.woff2, documented in
    # brgen/app/assets/stylesheets/_fonts_brand.scss as a licensed face whose
    # woff2 cannot be committed; the `src:` list starts with two `local()` entries
    # and the marketplace surface names an Arial fallback, so the design already
    # assumes the fetch fails. Recorded rather than removed: dropping the url()
    # would silently break the documented plan of dropping the files in.
    #
    # 2 are lg.svg, lightGallery's IE9 fallback, once per vendored copy. It sits
    # last in a `src:` list behind woff2/woff/ttf, so no browser that exists asks
    # for it, and adding a file nothing requests is worse than recording it. The
    # two copies are themselves the register's `rails_duplicate_vendor_css`.
    BASELINES = { "missing_asset" => 4 }.freeze

    Finding = Struct.new(:kind, :ref, :sheet, :tried)

    module_function

    def engine_dirs = Dir.glob(File.join(RAILS_ROOT, "brgen/engines/*"))

    # Both places a url() can be written: a stylesheet, and the inline <style>
    # blocks the mailer layout and brgen's legal footer use because an email and
    # a static legal page cannot load a bundle.
    def sheets
      pipeline = TREES.flat_map { |t| Dir.glob(File.join(RAILS_ROOT, t, "app/assets/stylesheets/**/*.{scss,css}")) } +
                 engine_dirs.flat_map { |d| Dir.glob(File.join(d, "app/assets/stylesheets/**/*.{scss,css}")) }
      served = TREES.flat_map { |t| Dir.glob(File.join(RAILS_ROOT, t, "public/**/*.css")) }
      views = TREES.flat_map { |t| Dir.glob(File.join(RAILS_ROOT, t, "app/views/**/*.erb")) } +
              engine_dirs.flat_map { |d| Dir.glob(File.join(d, "app/views/**/*.erb")) }
      (pipeline + served + views).reject { |path| path.include?("/builds/") || path.include?("/public/assets/") }
    end

    def body_of(path)
      raw = File.read(path, encoding: "UTF-8")
      css = path.end_with?(".erb") ? raw.scan(%r{<style[^>]*>(.*?)</style>}m).flatten.join("\n") : raw
      css.gsub(%r{/\*.*?\*/}m, " ").gsub(%r{(?<!:)//[^\n]*}, " ")
    end

    # `@each $w in (400, 600, 700)` builds three refs from one url(). Without
    # expanding it the interpolated ref resolves to nothing and reads as one
    # missing file rather than three, or gets skipped as unresolvable — either
    # way the count is wrong.
    #
    # Scoped to the *enclosing* loop, by brace matching, not to any loop naming
    # the same variable. _fonts_brand.scss has two `@each $w` blocks over
    # different weight lists; reading both reported PP Neue Montreal in five
    # weights when the source asks for three, and two of the five names appeared
    # in no stylesheet at all. A lint that invents a filename cannot be trusted
    # about the ones it did not invent.
    def each_blocks(body)
      body.enum_for(:scan, /@each\s+\$(\w+)\s+in\s+\(([^)]*)\)\s*\{/).map do
        var, list = Regexp.last_match(1), Regexp.last_match(2)
        open_at = Regexp.last_match.end(0) - 1
        { var:, values: list.split(",").map { |v| v.strip.delete('"\'') },
          range: (open_at..block_end(body, open_at)) }
      end
    end

    def block_end(body, open_at)
      depth = 0
      (open_at...body.length).each do |i|
        depth += 1 if body[i] == "{"
        if body[i] == "}"
          depth -= 1
          return i if depth.zero?
        end
      end
      body.length - 1
    end

    def expand(ref, offset, blocks)
      refs = [ ref ]
      ref.scan(/\#\{\$(\w+)\}/).flatten.uniq.each do |var|
        block = blocks.select { |b| b[:var] == var && b[:range].cover?(offset) }.min_by { |b| b[:range].size }
        next unless block

        refs = refs.flat_map { |r| block[:values].map { |v| r.gsub("\#{$#{var}}", v) } }
      end
      refs.reject { |r| r.include?("\#{") }
    end

    def refs_in(path)
      body = body_of(path)
      blocks = each_blocks(body)
      body.enum_for(:scan, /(?<![\w-])url\(\s*([^)]+?)\s*\)/).flat_map do
        ref = Regexp.last_match(1).strip.delete('"\'')
        offset = Regexp.last_match.begin(0)
        next [] if ref.empty? || ref.start_with?("data:", "http:", "https:", "//", "#")

        expand(ref, offset, blocks)
      end
    end

    def tree_of(path)
      rel = path.sub("#{RAILS_ROOT}/", "")
      rel.start_with?("brgen/engines/") ? "brgen" : rel.split("/").first
    end

    # Every root that serves this stylesheet. `shared/public` reaches all three
    # apps through the engine's static middleware, so one copy there satisfies
    # everyone; a file in only one app's `public/` satisfies only that app, which
    # is why a shared stylesheet needs the file in shared or in all three.
    def roots_for(path)
      tree = tree_of(path)
      return [ File.join(RAILS_ROOT, tree, "public"), File.join(RAILS_ROOT, "shared", "public"),
              File.join(RAILS_ROOT, tree, "app/assets") ] if APPS.include?(tree)

      [ File.join(RAILS_ROOT, "shared", "public"), File.join(RAILS_ROOT, "shared", "app/assets") ]
    end

    def satisfied_everywhere?(ref, path)
      return true if satisfied?(ref, roots_for(path))
      return false if APPS.include?(tree_of(path))

      APPS.all? { |app|
 satisfied?(ref, [ File.join(RAILS_ROOT, app, "public"), File.join(RAILS_ROOT, app, "app/assets") ]) }
    end

    # A root-absolute ref is a path under the root. A relative one is resolved
    # against the stylesheet when the stylesheet is itself served from public/,
    # and by basename when the pipeline resolves it — propshaft flattens
    # app/assets, so `url("logo.svg")` finds it at any depth.
    def satisfied?(ref, roots)
      clean = ref.sub(/[?#].*\z/, "")
      roots.any? do |root|
        next false unless File.directory?(root)

        if clean.start_with?("/")
          File.exist?(File.join(root, clean))
        else
          Dir.glob(File.join(root, "**", File.basename(clean))).any?
        end
      end
    end

    def scan
      sheets.flat_map do |path|
        refs_in(path).uniq.filter_map do |ref|
          next if satisfied_everywhere?(ref, path)

          Finding.new("missing_asset", ref, rel(path), roots_for(path).map { |r| rel(r) }.join(", "))
        end
      end
    end

    def rel(path) = path.to_s.sub("#{RAILS_ROOT}/", "")

    def counts(findings = scan)
      BASELINES.keys.to_h { |kind| [ kind, findings.count { |f| f.kind == kind } ] }
    end

    def over_baseline(findings = scan)
      counts(findings).filter_map do |kind, count|
        baseline = BASELINES.fetch(kind)
        "#{kind}: #{count} (baseline #{baseline}, +#{count - baseline})" if count > baseline
      end
    end

    def run
      findings = scan
      counts(findings).each do |kind, count|
        baseline = BASELINES.fetch(kind)
        note = count < baseline ? " — under baseline, lower it" : ""
        puts "asset_url_lint: #{kind} #{count} (baseline #{baseline})#{note}"
      end
      findings.sort_by(&:ref).each { |f| puts format("  %-52s %s", f.ref, f.sheet) }

      exceeded = over_baseline(findings)
      return true if exceeded.empty?

      warn "asset_url_lint: exceeds baseline — #{exceeded.join("; ")}"
      false
    end
  end
end

exit(Pub4::AssetUrlLint.run ? 0 : 1) if $PROGRAM_NAME == __FILE__
