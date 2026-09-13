# frozen_string_literal: true

module Deploy
  # A filesystem near full, by blocks or by inodes.
  #
  # Nothing on the box watched either. A full /home stops every SQLite write the
  # apps make and the deploy's copy-tree extraction with it, and inodes run out
  # first on a tree of small files — which a Rails checkout and its asset
  # builds are. The failure it prevents looks like a database error, not a disk.
  #
  # Reads `df -ik`, whose header names the columns on OpenBSD and macOS alike, so
  # the parse keys on the header rather than on column positions.
  module DiskUsage
    LIMIT_PERCENT = 90

    module_function

    def failures(df_output, limit: LIMIT_PERCENT)
      lines = df_output.to_s.lines.map(&:split).reject(&:empty?)
      header = lines.shift
      return ["disk: df printed no header"] unless header

      capacity = header.index("Capacity")
      iused = header.index("%iused")
      return ["disk: df -ik has no Capacity or %iused column"] unless capacity && iused

      lines.flat_map do |row|
        mount = row.last
        { "blocks" => row[capacity], "inodes" => row[iused] }.filter_map do |what, value|
          percent = value.to_s.delete("%").to_i
          "disk: #{mount} #{what} #{percent}% used" if percent >= limit
        end
      end
    end
  end
end
