# frozen_string_literal: true

module MASTER
  # FileProcessor - 4-phase file processing
  # Clean -> Rename/Rephrase -> Structural Transform -> Expand/Contract
  module FileProcessor
    PHASES = %i[clean rename transform assess].freeze

    class << self
      # Process a file through all 4 phases
      def process(content, filename: "file", dry_run: true)
        log("file0: processing #{File.basename(filename)}")
        result = { filename: filename, original: content, phases: {} }
        current = content

        PHASES.each do |phase|
          phase_result = send(:"phase_#{phase}", current, filename)
          result[:phases][phase] = phase_result
          current = phase_result[:output] unless dry_run && phase_result[:changes].any?
        end

        result[:final] = current
        result[:changed] = current != content
        log("file0: #{result[:changed] ? 'changed' : 'unchanged'}")
        result
      end

      # Process entire directory
      def process_directory(path, dry_run: true)
        patterns = %w[*.rb *.py *.js *.ts *.go *.rs *.md *.yml *.yaml]
        files = patterns.flat_map { |p| Dir.glob(File.join(path, "**", p)) }
        log("file0: scanning #{files.size} files in #{path}")
        results = []

        files.each do |file|
          content = File.read(file)
          result = process(content, filename: file, dry_run: dry_run)

          if result[:changed] && !dry_run
            File.write(file, result[:final])
            log("file0: wrote #{File.basename(file)}")
          end

          results << result if result[:changed]
        end

        { files_checked: files.size, files_changed: results.size, results: results }
      end

      def log(msg)
        puts UI.dim(msg)
      end

      private

      # Phase 1: Clean - deterministic hygiene
      def phase_clean(content, filename)
        changes = []
        output = content.dup

        # CRLF -> LF
        if output.include?("\r\n")
          output.gsub!("\r\n", "\n")
          changes << "CRLF -> LF"
        end

        # Trailing whitespace
        if output.match?(/[ \t]+$/)
          output.gsub!(/[ \t]+$/, "")
          changes << "Trailing whitespace removed"
        end

        # BOM
        if output.start_with?("\xEF\xBB\xBF")
          output = output[3..]
          changes << "BOM removed"
        end

        # Zero-width characters
        if output.match?(/[\u200B\u200C\u200D\uFEFF]/)
          output.gsub!(/[\u200B\u200C\u200D\uFEFF]/, "")
          changes << "Zero-width characters removed"
        end

        # Ensure final newline
        unless output.end_with?("\n")
          output += "\n"
          changes << "Final newline added"
        end

        # Normalize indentation (tabs -> spaces for non-Makefile)
        if !filename.include?("Makefile") && output.include?("\t")
          output.gsub!(/\t/, "  ")
          changes << "Tabs -> spaces"
        end

        { phase: :clean, changes: changes, output: output }
      end

      # Phase 2: Rename/Rephrase - improve naming
      def phase_rename(content, filename)
        changes = []
        output = content.dup

        # get_ prefix removal (Ruby convention)
        renames = output.scan(/def\s+get_(\w+)/).flatten
        renames.each do |name|
          # Only rename if not a collision
          unless output.match?(/def\s+#{name}\b/)
            output.gsub!(/\bget_#{name}\b/, name)
            changes << "get_#{name} -> #{name}"
          end
        end

        # Verbose suffixes
        {
          "_value" => "",
          "_data" => "",
          "_info" => "",
          "_object" => "",
        }.each do |suffix, replacement|
          output.scan(/def\s+(\w+#{suffix})\b/).flatten.each do |method|
            new_name = method.sub(suffix, replacement)
            unless output.match?(/def\s+#{new_name}\b/)
              output.gsub!(/\b#{method}\b/, new_name)
              changes << "#{method} -> #{new_name}"
            end
          end
        end

        # Boolean method naming
        output.scan(/def\s+(is_\w+)\b/).flatten.each do |method|
          new_name = method.sub(/^is_/, "") + "?"
          unless output.match?(/def\s+#{Regexp.escape(new_name)}\b/)
            output.gsub!(/\b#{method}\b(?!\?)/, new_name)
            changes << "#{method} -> #{new_name}"
          end
        end

        { phase: :rename, changes: changes, output: output }
      end

      # Phase 3: Structural Transform - apply structural axioms
      def phase_transform(content, filename)
        changes = []
        output = content.dup

        # STRUCTURAL_REFLOW: reorder by importance
        if filename.end_with?(".rb")
          reflow_result = Reflow.analyze(output, filename: filename)
          if reflow_result[:issues].any?
            output = Reflow.reflow(output, filename: filename)
            changes << "Reflowed by importance"
          end
        end

        # STRUCTURAL_MERGE: combine duplicate requires
        requires = output.scan(/^require\s+['"]([^'"]+)['"]/).flatten
        duplicates = requires.select { |r| requires.count(r) > 1 }.uniq
        duplicates.each do |req|
          # Keep first, remove rest
          first = true
          output.gsub!(/^require\s+['"]#{Regexp.escape(req)}['"]\n/) do
            if first
              first = false
              $&
            else
              changes << "Removed duplicate require '#{req}'"
              ""
            end
          end
        end

        # STRUCTURAL_FLATTEN: early returns
        # Simple pattern: if condition / long block / else / short / end

        { phase: :transform, changes: changes, output: output }
      end

      # Phase 4: Expand/Contract Assessment - evaluate size changes
      def phase_assess(content, filename)
        changes = []
        output = content

        original_lines = content.lines.size
        original_bytes = content.bytesize

        # Assess if file should be split
        if original_lines > 300
          changes << "Consider splitting: #{original_lines} lines exceeds 300 limit"
        end

        # Assess if file is too small (maybe merge with related)
        if original_lines < 20 && !filename.match?(/test|spec|config/)
          changes << "Consider merging: #{original_lines} lines may be too granular"
        end

        # Check method count
        method_count = content.scan(/^\s*def\s+/).size
        if method_count > 15
          changes << "High method count (#{method_count}): consider splitting by responsibility"
        end

        # Check class count
        class_count = content.scan(/^\s*class\s+/).size
        if class_count > 1
          changes << "Multiple classes (#{class_count}): one class per file preferred"
        end

        {
          phase: :assess,
          changes: changes,
          output: output,
          metrics: {
            lines: original_lines,
            bytes: original_bytes,
            methods: method_count,
            classes: class_count,
          },
        }
      end
    end
  end
end
