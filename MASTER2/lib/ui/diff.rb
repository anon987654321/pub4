# frozen_string_literal: true

module MASTER
  module DiffView
    extend self

    # Generate a unified diff between original and modified content
    def unified_diff(original, modified, filename: "file", context_lines: 3)
      original_lines = original.lines.map(&:chomp)
      modified_lines = modified.lines.map(&:chomp)

      output = []
      output << "--- a/#{filename}"
      output << "+++ b/#{filename}"

      # Use a simple line-by-line comparison for now
      hunks = compute_hunks(original_lines, modified_lines, context_lines)

      hunks.each do |hunk|
        output << hunk[:header]
        output.concat(hunk[:lines])
      end

      "#{output.join("\n")}\n"
    end

    private

    def compute_hunks(original, modified, context)
      # Find all differences
      changes = []
      max_len = [original.length, modified.length].max

      (0...max_len).each do |idx|
        orig_line = original[idx]
        mod_line = modified[idx]

        changes << if orig_line == mod_line
                     { type: :same, orig: idx, mod: idx }
                   elsif orig_line.nil?
                     { type: :add, orig: idx, mod: idx }
                   elsif mod_line.nil?
                     { type: :delete, orig: idx, mod: idx }
                   else
                     # Line changed
                     { type: :change, orig: idx, mod: idx }
                   end
      end

      # Group into hunks
      hunks = []
      idx = 0

      while idx < changes.length
        # Skip unchanged lines that are far from changes
        while idx < changes.length && changes[idx][:type] == :same
          # Look ahead to find next change
          next_change = find_next_change(changes, idx)
          break if next_change && (next_change - idx) <= context * 2

          idx += 1
        end

        next if idx >= changes.length

        # Start a new hunk
        hunk_start = [idx - context, 0].max

        # Find end of hunk (include context after last change)
        hunk_end = idx
        while hunk_end < changes.length
          if changes[hunk_end][:type] == :same
            # Check if there's another change within context
            next_change = find_next_change(changes, hunk_end)
            if next_change && (next_change - hunk_end) <= context * 2
              hunk_end = next_change
            else
              # No more changes nearby, add context and stop
              hunk_end = [hunk_end + context, changes.length].min
              break
            end
          else
            # Found a change, continue
            hunk_end += 1
          end
        end

        # Build this hunk
        orig_start = changes[hunk_start][:orig]
        mod_start = changes[hunk_start][:mod]
        orig_count = 0
        mod_count = 0
        lines = []

        (hunk_start...hunk_end).each do |jdx|
          change = changes[jdx]
          case change[:type]
          when :same
            lines << " #{original[change[:orig]]}"
            orig_count += 1
            mod_count += 1
          when :delete
            lines << "-#{original[change[:orig]]}" if change[:orig] < original.length
            orig_count += 1
          when :add
            lines << "+#{modified[change[:mod]]}" if change[:mod] < modified.length
            mod_count += 1
          when :change
            lines << "-#{original[change[:orig]]}" if change[:orig] < original.length
            lines << "+#{modified[change[:mod]]}" if change[:mod] < modified.length
            orig_count += 1
            mod_count += 1
          end
        end

        unless lines.empty?
          hunks << {
            header: "@@ -#{orig_start + 1},#{orig_count} +#{mod_start + 1},#{mod_count} @@",
            lines: lines,
          }
        end

        idx = hunk_end
      end

      hunks
    end

    def find_next_change(changes, start)
      (start...changes.length).each do |idx|
        return idx if changes[idx][:type] != :same
      end
      nil
    end
  end
end
