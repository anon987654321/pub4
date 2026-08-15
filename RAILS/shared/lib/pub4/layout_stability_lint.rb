# frozen_string_literal: true

require "set"

module Pub4
  # Ratchet: nothing on a page may change size after it has been painted.
  #
  # This is the other half of "well proportioned". ScaleLint asks whether the
  # numbers come from one scale; this asks whether the layout those numbers
  # describe holds still while the page loads. They are different defects and
  # only the second one is visible to a user -- a card that is 0px tall until its
  # photo arrives and then 240px tall shoves everything below it down, and the
  # reader loses their place. Google names the measurement Cumulative Layout
  # Shift; the causes are a short list and every one of them is legible in
  # source.
  #
  # Three kinds:
  #
  #   unreserved_media   an <img>/image_tag with neither width+height attributes
  #                      nor a class whose CSS reserves the box (aspect-ratio,
  #                      an explicit height, or contain-intrinsic-size). This is
  #                      the overwhelming majority of real CLS.
  #   layout_transition  a `transition` naming width/height/top/margin/`all`.
  #                      Those animate on the layout thread: every frame is a
  #                      reflow of everything after the element, which is the
  #                      difference between a smooth open and a stuttering one.
  #                      transform and opacity are the compositor-only pair.
  #   font_without_display  an @font-face with no font-display. The default is
  #                      `auto`, which most browsers render as `block`: text is
  #                      invisible for up to three seconds and then arrives at a
  #                      different width than the fallback it replaced.
  #
  # Deliberately source-level. A headless-browser CLS measurement is the more
  # direct instrument and this tree already has one path for that
  # (RAILS/gates/rendered_gates), but browser gates belong on the deploy host --
  # they monopolise a machine for an hour. This runs in milliseconds on every
  # check and catches the cause rather than the symptom.
  module LayoutStabilityLint
    RAILS_ROOT = File.expand_path("../../..", __dir__)
    OPT_OUT = "layout: ok"

    SKIP = %r{/(node_modules|vendor|builds|public/assets|tmp)/}

    # A declaration that gives the box a size before its content arrives.
    RESERVING = /(?:aspect-ratio|contain-intrinsic-size|(?<![-\w])height)\s*:/

    # Properties whose animation is a reflow. `all` is the worst of them: it
    # animates whatever happens to change, which on a class toggle is usually
    # geometry.
    LAYOUT_PROPS = %w[
      all width height min-width min-height max-width max-height
      top right bottom left inset margin margin-top margin-right
      margin-bottom margin-left padding font-size
    ].freeze

    Finding = Struct.new(:file, :line, :kind, :detail)

    module_function

    def stylesheets
      @stylesheets ||= (
        Dir.glob(File.join(RAILS_ROOT, "*/app/assets/stylesheets/**/*.{scss,css}")) +
        Dir.glob(File.join(RAILS_ROOT, "*/engines/*/app/assets/stylesheets/**/*.{scss,css}")) +
        Dir.glob(File.join(RAILS_ROOT, "shared/app/assets/stylesheets/**/*.{scss,css}"))
      ).uniq.sort.reject { |path| path.match?(SKIP) }
    end

    def views
      @views ||= (
        Dir.glob(File.join(RAILS_ROOT, "*/app/views/**/*.erb")) +
        Dir.glob(File.join(RAILS_ROOT, "*/engines/*/app/views/**/*.erb")) +
        Dir.glob(File.join(RAILS_ROOT, "shared/app/views/**/*.erb"))
      ).uniq.sort.reject { |path| path.match?(SKIP) }
    end

    def strip_comments(raw)
      raw.gsub(%r{/\*.*?\*/}m) { |b| b.gsub(/[^\n]/, " ") }
         .gsub(%r{//[^\n]*}) { |l| " " * l.length }
    end

    def source_lines(path) = strip_comments(File.read(path, encoding: "UTF-8")).lines

    def opted_out?(lines, index)
      [lines[index], index.positive? ? lines[index - 1] : nil]
        .compact.any? { |line| line.include?(OPT_OUT) }
    end

    # Class names whose CSS reserves a box.
    #
    # Deliberately generous: a class counts as reserved if ANY rule mentioning
    # it declares a reservation. SCSS nesting means a selector line does not
    # carry its own full ancestry (`&__img` resolves at build time, not here),
    # so a stricter reading would report classes that are in fact sized and send
    # the next author chasing a value that is already there. The lint's job is to
    # find the media nobody sized at all.
    def reserved_classes
      @reserved_classes ||= begin
        found = Set.new
        stylesheets.each do |path|
          body = strip_comments(File.read(path, encoding: "UTF-8"))
          body.scan(/([^{}]+)\{([^{}]*)\}/m) do |selector, block|
            next unless block.match?(RESERVING)

            selector.scan(/\.([a-zA-Z][\w-]*)/) { |name| found << name.first }
          end
        end
        found
      end
    end

    # <img ...> written by hand, and image_tag/video_tag through the helper.
    MEDIA = /<(?:img|video|iframe)\b[^>]*>|(?:image_tag|video_tag)\s*\(?[^%]*/

    def sized?(tag)
      return true if tag.match?(/\bwidth\s*[:=]/) && tag.match?(/\bheight\s*[:=]/)
      return true if tag.match?(/\bsize\s*:/)
      return true if tag.match?(/\bstyle\s*=\s*"[^"]*aspect-ratio/)

      tag.scan(/class\s*[:=]\s*[("']?([^"')]*)/).flatten.join(" ")
         .scan(/[\w-]+/).any? { |name| reserved_classes.include?(name) }
    end

    def media_findings
      views.flat_map do |path|
        lines = source_lines(path)
        lines.each_with_index.flat_map do |line, index|
          next [] if opted_out?(lines, index)

          line.scan(MEDIA).flat_map do |tag|
            next [] if sized?(tag)

            [Finding.new(rel(path), index + 1, "unreserved_media", tag.to_s.strip[0, 90])]
          end
        end
      end
    end

    TRANSITION = /(?<![-\w])transition(?:-property)?\s*:\s*([^;{}]+)[;}]/

    def transition_findings
      stylesheets.flat_map do |path|
        lines = source_lines(path)
        lines.each_with_index.flat_map do |line, index|
          next [] if opted_out?(lines, index)

          line.scan(TRANSITION).flatten.flat_map do |value|
            named = LAYOUT_PROPS.select { |prop| value.match?(/(?<![-\w])#{Regexp.escape(prop)}(?![-\w])/) }
            next [] if named.empty?

            [Finding.new(rel(path), index + 1, "layout_transition", named.join(", "))]
          end
        end
      end
    end

    def font_findings
      stylesheets.flat_map do |path|
        body = strip_comments(File.read(path, encoding: "UTF-8"))
        offset = 0
        body.scan(/@font-face\s*\{([^{}]*)\}/m).flat_map do |block,|
          offset = body.index(block, offset).to_i
          next [] if block.match?(/font-display\s*:/)

          line = body[0, offset].count("\n") + 1
          family = block[/font-family\s*:\s*([^;]+);/, 1].to_s.strip
          [Finding.new(rel(path), line, "font_without_display", family)]
        end
      end
    end

    def findings = media_findings + transition_findings + font_findings

    def counts = findings.group_by(&:kind).transform_values(&:size)

    def rel(path) = path.sub("#{RAILS_ROOT}/", "")

    # Measured 2026-08-16.
    #
    # unreserved_media is the number that matters and the one worth driving to
    # zero: every one of them is a photo whose box is 0px until it arrives.
    # layout_transition is three sites -- two `all` and one `width` -- which is
    # low enough that the next one is a new one rather than a backlog.
    # font_without_display is already zero: all ten @font-face blocks declare it.
    BASELINES = {
      "unreserved_media" => 34,
      "layout_transition" => 3,
      "font_without_display" => 0,
    }.freeze
  end
end
