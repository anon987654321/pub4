# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Fix
    class FixLoop
      # Where the last run's repair stream ran out of budget, per target. A pass
      # repairs files in scan order until its budget ends, about a minute a file,
      # so a run reaches thirty-odd of MASTER's twelve hundred; starting every
      # run from the top repaired bin/ and lib/cli/ again and never reached the
      # rest. The next run starts where the last one stopped, and a stream that
      # reaches the end clears the mark.
      module StreamCursor
        module_function

        # files, rotated so the recorded file comes first; unchanged without one.
        def order(root, target, files)
          start = files.index(read(root)[key(root, target)].then { |rel| rel && File.join(root, rel) })
          start ? files.rotate(start) : files
        end

        # path is where the stream stopped, or nil when it reached the end.
        def write(root, target, path)
          marks = read(root)
          path ? marks[key(root, target)] = relative(root, path) : marks.delete(key(root, target))
          FileUtils.mkdir_p(File.dirname(file(root)))
          File.write(file(root), JSON.pretty_generate(marks) + "\n")
        rescue SystemCallError => e
          Master::Ground::Swallow.log(e, context: "fix.stream_cursor")
        end

        def read(root)
          File.file?(file(root)) ? JSON.parse(File.read(file(root))) : {}
        rescue JSON::ParserError
          {}
        end

        def file(root) = File.join(root, ".master", "fix_stream_cursor.json")
        def key(root, target) = relative(root, target.to_s)
        def relative(root, path) = File.expand_path(path).delete_prefix("#{File.expand_path(root)}/")
      end
    end
  end
end
