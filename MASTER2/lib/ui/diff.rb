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

      output.join("\n") + "\n"
    end

    private

    def compute_hunks(original, modified, context)
      # Find all differences
      changes = []
      max_len = [original.length, modified.length].max

      (0...max_len).each do |i|
        orig_line = original[i]
        mod_line = modified[i]

        if orig_line == mod_line
          changes << { type: :same, orig: i, mod: i }
        elsif orig_line.nil?
          changes << { type: :add, orig: i, mod: i }
        elsif mod_line.nil?
          changes << { type: :delete, orig: i, mod: i }
        else
          # Line changed
          changes << { type: :change, orig: i, mod: i }
        end
      end

      # Group into hunks
      hunks = []
      i = 0

      while i < changes.length
        # Skip unchanged lines that are far from changes
        while i < changes.length && changes[i][:type] == :same
          # Look ahead to find next change
          next_change = find_next_change(changes, i)
          break if next_change && (next_change - i) <= context * 2
          i += 1
        end

        next if i >= changes.length

        # Start a new hunk
        hunk_start = [i - context, 0].max

        # Find end of hunk (include context after last change)
        hunk_end = i
        while hunk_end < changes.length
          if changes[hunk_end][:type] != :same
            # Found a change, continue
            hunk_end += 1
          else
            # Check if there's another change within context
            next_change = find_next_change(changes, hunk_end)
            if next_change && (next_change - hunk_end) <= context * 2
              hunk_end = next_change
            else
              # No more changes nearby, add context and stop
              hunk_end = [hunk_end + context, changes.length].min
              break
            end
          end
        end

        # Build this hunk
        orig_start = changes[hunk_start][:orig]
        mod_start = changes[hunk_start][:mod]
        orig_count = 0
        mod_count = 0
        lines = []

        (hunk_start...hunk_end).each do |j|
          change = changes[j]
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
            lines: lines
          }
        end

        i = hunk_end
      end

      hunks
    end

    def find_next_change(changes, start)
      (start...changes.length).each do |i|
        return i if changes[i][:type] != :same
      end
      nil
    end
  end
end
