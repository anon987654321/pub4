# frozen_string_literal: true

require "tmpdir"
require_relative "../../checks/support/pixel_match"

module Master
  module Fix
    # The independent visual reviewer. The agent that proposed a visual repair never approves it:
    # this asks a separate reviewer, with the changed boxes cropped and enlarged 400% and the
    # computed values the sweep measured, to judge against the Laws only, and to explain every
    # changed region. An unexplained region is a rejection.
    module VisualReviewer
      CROPS = 6

      BRIEF = <<~TEXT
        INDEPENDENT VISUAL REVIEW
        You did not make this change and you are not asked to improve it. Judge it against the MASTER
        Laws named below and nothing else: not taste, not a look. The principles behind those Laws are
        the Swiss/International typographic style, Bringhurst on measure, scale and rhythm, and
        Mueller-Brockmann's grid systems; apply them as measurements, not as a style to imitate.

        The attached images are the changed regions of the re-rendered page, cropped and enlarged 400%
        so edges, alignment and baselines read at the pixel. Each is listed as R<n> x,y wxh below,
        followed by the findings and computed values the browser reported.
        Answer APPROVE or REJECT on the first line. After APPROVE give one line a region,
        "R<n>: <which Law this change satisfies and how>"; a region you cannot explain means REJECT.
      TEXT

      module_function

      # :approved, or why not. reviewer ->(brief, images) { text }.
      def judge(group, regions, reviewer:)
        return "no independent reviewer configured" unless reviewer

        verdict(reviewer.call(brief(group, regions), crops(group, regions)).to_s, regions)
      end

      def brief(group, regions)
        boxes = regions.each_with_index.map { |box, index| "R#{index + 1} #{box[:x]},#{box[:y]} #{box[:w]}x#{box[:h]}" }
        [BRIEF, "Laws: #{group.law}", "Changed regions:", *boxes, "Findings:", group.evidence].join("\n")
      end

      def crops(group, regions)
        after = group.after.first
        return [] unless after && File.file?(after)

        dir = Dir.mktmpdir("visual-review")
        regions.first(CROPS).each_with_index.map do |box, index|
          Deploy::PixelMatch.crop(after, box, out: File.join(dir, "R#{index + 1}.png"))
        end
      end

      def verdict(text, regions)
        first = text.lines.first.to_s.strip
        return "rejected: #{first.sub(/\AREJECT:?\s*/, "")[0, 160]}" unless first.start_with?("APPROVE")

        missing = regions.each_index.find { |index| !text.match?(/^R#{index + 1}:/) }
        missing ? "rejected: R#{missing + 1} left unexplained" : :approved
      end
    end
  end
end
