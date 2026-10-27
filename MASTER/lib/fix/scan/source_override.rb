# frozen_string_literal: true

module Master
  module Fix
    module Scan

      # A text that stands in for a file's bytes on disk while a block runs, so a scan can judge a
      # version that is not the working tree's: the staged blob a commit will hold, or the base a
      # change is measured against. The real path is kept, so path guards, law dispatch and reports
      # still name the file. The file processor and the external linters ask here before the disk.
      # Held per thread: the scanner runs a file's laws on the thread that asked for it, and a /fix
      # pass scanning the same path on another thread must still read the disk.
      module SourceOverride

        KEY = :master_scan_source_override

        module_function

        # Runs the block with each path in +sources+ ({path => text}) read as its text.
        def with(sources)
          previous = Thread.current.thread_variable_get(KEY)
          merged = (previous || {}).merge(sources.to_h { |path, text| [File.expand_path(path.to_s), text.to_s] })
          Thread.current.thread_variable_set(KEY, merged.freeze)
          yield
        ensure
          Thread.current.thread_variable_set(KEY, previous)
        end

        # The text standing in for +path+, or nil when the disk is the source.
        def for(path)
          Thread.current.thread_variable_get(KEY)&.fetch(File.expand_path(path.to_s), nil)
        end

        # The override as the file processor reads a file: nil when the disk is the source,
        # otherwise a Result of the text, refused as a file would be when binary or too large.
        def read(path, max_bytes:)
          text = self.for(path)
          return unless text
          return Result.err("binary file skipped: #{path}", category: :validation) if text.include?("\0")
          return Result.err("file too large: #{path}", category: :validation) if text.bytesize > max_bytes

          Result.ok(text.dup.force_encoding(Encoding::UTF_8))
        end
      end
    end
  end
end
