# frozen_string_literal: true

module Master
  module Reach
    class StrReplace
      include Base
      TIER = :guarded
      NAME = "str_replace".freeze
      DESCRIPTION = "Replace unique string in a file. Fails if pattern matches 0 or 2+ times.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root, @undo, @governor, @bus, @diff_stager =
          File.realpath(root), undo, governor, event_bus, diff_stager
      end

      def call(path:, old_string:, new_string:)
        safely do
          resolved = resolve(path)
          next resolved if resolved.err?

          full = resolved.value!
          next Result.err("not found: #{path}", category: :validation) unless File.exist?(full)

          content = File.read(full)
          updated = resolve_updated_content(content, old_string, new_string, path)
          next updated if updated.is_a?(Result::Err)

          perm = permit(path)
          next perm if perm.err?

          commit_write(full, updated, path:)
        end
      end

      def resolve_updated_content(content, old_string, new_string, path)
        anchor = Hashline.parse_anchor(old_string)
        if anchor
          line = content.lines[anchor[:line] - 1]
          return Result.err("hashline: line #{anchor[:line]} missing in #{path}", category: :validation) unless line

          replaced = Hashline.replace_line(content, line_no: anchor[:line], id: anchor[:id], new_line: new_string)
          return replaced if replaced.err?

          replaced.value!
        else
          count = content.scan(old_string).size
          return Result.err("str_replace: pattern not found in #{path}", category: :validation) if count.zero?
          return Result.err("str_replace: pattern matches #{count} times in #{path} (must be unique)",
                          category: :validation) if count > 1

          content.sub(old_string, new_string)
        end
      end
    end
  end
end
