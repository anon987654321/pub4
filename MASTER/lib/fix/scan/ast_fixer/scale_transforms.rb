# frozen_string_literal: true

require_relative "../../../design/scale"

module Master
  module Fix
    module Scan
      class AstFixer
        # EIGHT_PX_RHYTHM and LINE_HEIGHT_ON_SCALE's repair, on the rules they
        # detect with (Master::Design::Scale): each off-scale step moves to the
        # nearest declared one in the unit it was written in. What the Laws do
        # not read (comments, a `scale: ok` line or the line under one, computed
        # values, token definitions) the repair does not touch, so a finding
        # /fix cannot clear and a change no Law asked for are both ruled out.
        module ScaleTransforms
          private

          def snap_to_design_scale(src)
            previous = ""
            in_comment = false
            lines = src.each_line.map do |line|
              skip = line.include?(Design::Scale::OPT_OUT) || previous.include?(Design::Scale::OPT_OUT) ||
                     in_comment || line.strip.start_with?("//", "/*")
              previous = line
              in_comment = still_in_block_comment?(line, in_comment)
              skip ? line : snap_declarations(line)
            end

            out = lines.join
            @transforms << :design_scale if out != src
            out
          end

          # A line leaves a block comment open when it was open and closes nowhere
          # on the line, or when its last /* has no */ after it.
          def still_in_block_comment?(line, open)
            return !line.include?("*/") if open

            line.include?("/*") && !line.rpartition("/*").last.include?("*/")
          end

          def snap_declarations(line)
            scale = Master::Review::Scan::Laws.design_scale
            line.gsub(Design::Scale::DECLARATION) do |declaration|
              match = Regexp.last_match
              snapped = scale.snap(match[:prop], match[:value])
              snapped ? declaration.sub(match[:value], snapped) : declaration
            end
          end
        end
      end
    end
  end
end
