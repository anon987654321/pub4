module MASTER
  module SelfEnforce
    extend self

    def lib_path
      @lib_path ||= File.expand_path("../lib", __dir__)
    end

    TARGET_FILE_COUNT = 25
    MAX_FILE_COUNT = 30
    FORBIDDEN_SUFFIXES = %w[_helper _bridge _wrapper _utils _util].freeze
    FORBIDDEN_PATTERNS = [
      /rescue\s*$/,
      /rescue\s*;/,
      /rescue\s*=>/
    ].freeze

    def run_all_checks
      violations = []
      violations += check_file_count
      violations += check_forbidden_suffixes
      violations += check_bare_rescues
      violations += check_comment_density
      violations += check_file_sizes
      violations += check_logic_inconsistencies
      violations += check_code_smells
      violations += check_naming_consistency
      violations += check_duplicated_logic
      violations
    end

    def check_file_count
      rb_files = Dir[File.join(lib_path, "*.rb")]
      count = rb_files.size
      
      return [] if count <= MAX_FILE_COUNT
      
      [{
        axiom: :ULTRA_MINIMALISM,
        severity: count > 40 ? :error : :warn,
        file: "lib/",
        message: "lib/ has #{count} files (target: ≤#{TARGET_FILE_COUNT}, max: #{MAX_FILE_COUNT})",
        fix: "Merge small files into parent modules"
      }]
    end

    def check_forbidden_suffixes
      violations = []
      Dir[File.join(lib_path, "*.rb")].each do |file|
        basename = File.basename(file, ".rb")
        FORBIDDEN_SUFFIXES.each do |suffix|
          if basename.end_with?(suffix)
            violations << {
              axiom: :BE_CONCISE,
              severity: :warn,
              file: file,
              message: "Forbidden suffix '#{suffix}' in filename",
              fix: "Rename to describe what it IS, not what it DOES"
            }
          end
        end
      end
      violations
    end

    def check_bare_rescues
      violations = []
      Dir[File.join(lib_path, "**/*.rb")].each do |file|
        lines = File.readlines(file)
        lines.each_with_index do |line, idx|
          FORBIDDEN_PATTERNS.each do |pattern|
            if line =~ pattern && line !~ /rescue\s+\w+Error/
              violations << {
                axiom: :FAIL_VISIBLY,
                severity: :error,
                file: file,
                line: idx + 1,
                message: "Bare rescue without error class",
                fix: "Specify error class: rescue StandardError => e"
              }
            end
          end
        end
      end
      violations
    end

    def check_comment_density
      violations = []
      Dir[File.join(lib_path, "*.rb")].each do |file|
        next if file.end_with?("self_enforce.rb")
        
        lines = File.readlines(file)
        total_lines = lines.size
        comment_lines = lines.count { |l| l.strip.start_with?("#") && l !~ /frozen_string_literal|encoding:/ }
        
        next if total_lines.zero?
        
        density = (comment_lines.to_f / total_lines * 100).round(1)
        
        if density > 5.0
          violations << {
            axiom: :SELF_EXPLAINING,
            severity: :warn,
            file: file,
            message: "Comment density #{density}% (target: <5%)",
            fix: "Make code self-documenting, remove obvious comments"
          }
        end
      end
      violations
    end

    def check_file_sizes
      violations = []
      Dir[File.join(lib_path, "*.rb")].each do |file|
        lines = File.readlines(file).size
        
        if lines < 30
          violations << {
            axiom: :ULTRA_MINIMALISM,
            severity: :info,
            file: file,
            message: "File has only #{lines} lines (consider merging into parent)",
            fix: "Merge into related parent module"
          }
        elsif lines > 500
          violations << {
            axiom: :ONE_JOB,
            severity: :warn,
            file: file,
            message: "File has #{lines} lines (consider splitting)",
            fix: "Extract cohesive submodules to subdirectory"
          }
        end
      end
      violations
    end

    def auto_fix_all
      fixed = []
      
      fixed += auto_merge_small_files
      fixed += auto_strip_comments
      
      fixed
    end

    def auto_merge_small_files
      fixed = []
      small_files = Dir[File.join(lib_path, "*.rb")].select do |file|
        File.readlines(file).size < 30
      end
      
      small_files.each do |file|
        parent = suggest_parent_module(file)
        if parent
          fixed << { action: :merge, from: file, to: parent }
        end
      end
      
      fixed
    end

    def auto_strip_comments
      fixed = []
      Dir[File.join(lib_path, "**/*.rb")].each do |file|
        content = File.read(file)
        stripped = strip_obvious_comments(content)
        
        if content != stripped
          File.write(file, stripped)
          fixed << { action: :strip_comments, file: file }
        end
      end
      fixed
    end

    def strip_obvious_comments(content)
      lines = content.lines
      new_lines = []
      
      lines.each do |line|
        if line.strip.start_with?("#")
          keep = line =~ /frozen_string_literal|encoding:|TODO|FIXME|HACK|NOTE:/
          new_lines << line if keep
        else
          new_lines << line
        end
      end
      
      new_lines.join
    end

    def suggest_parent_module(file)
      basename = File.basename(file, ".rb")
      
      case basename
      when /firewall/ then "agent.rb"
      when /pool/ then "agent.rb"
      when /autocomplete/ then "commands.rb"
      when /keybinding/ then "commands.rb"
      when /helper/ then nil
      when /bridge/ then "replicate.rb"
      when /timeout/ then "llm.rb"
      when /context/ then "llm.rb"
      else
        nil
      end
    end

    def check_logic_inconsistencies
      violations = []
      Dir[File.join(lib_path, "**/*.rb")].each do |file|
        content = File.read(file)
        lines = content.lines
        
        lines.each_with_index do |line, idx|
          if line =~ /if\s+(.+)\s*$/
            condition = $1.strip
            
            if condition =~ /&&.*\|\|/ && !(condition =~ /\(.*\)/)
              violations << {
                axiom: :SIMPLEST_WORKS,
                severity: :warn,
                file: file,
                line: idx + 1,
                message: "Mixed && and || without parentheses - ambiguous precedence",
                fix: "Add parentheses to clarify: (a && b) || c"
              }
            end
            
            if condition =~ /\s==\s*true\b|\s==\s*false\b/
              violations << {
                axiom: :BE_CONCISE,
                severity: :info,
                file: file,
                line: idx + 1,
                message: "Comparing to true/false is redundant",
                fix: "Use 'if variable' or 'unless variable' directly"
              }
            end
            
            if condition =~ /!\s*!\s*/
              violations << {
                axiom: :SELF_EXPLAINING,
                severity: :info,
                file: file,
                line: idx + 1,
                message: "Double negation (!!) is unclear",
                fix: "Convert to explicit boolean or truthy check"
              }
            end
          end
          
          if line =~ /if\s+.*\s+then\s+.*\s+else\s+.*\s+end/ && line.length > 80
            violations << {
              axiom: :REFLOW,
              severity: :info,
              file: file,
              line: idx + 1,
              message: "One-line if/else/end is too long and hard to read",
              fix: "Break into multiple lines"
            }
          end
          
          if line =~ /return\s+if\b/ && lines[idx - 1] && lines[idx - 1] =~ /return\b/
            violations << {
              axiom: :SIMPLEST_WORKS,
              severity: :warn,
              file: file,
              line: idx + 1,
              message: "Consecutive returns - second may be unreachable",
              fix: "Review control flow logic"
            }
          end
        end
      end
      violations
    end

    def check_code_smells
      violations = []
      Dir[File.join(lib_path, "**/*.rb")].each do |file|
        content = File.read(file)
        lines = content.lines
        
        lines.each_with_index do |line, idx|
          if line =~ /\.nil\?\s*\?\s*.*:\s*.*/
            violations << {
              axiom: :BE_CONCISE,
              severity: :info,
              file: file,
              line: idx + 1,
              message: "Ternary for nil check can use ||",
              fix: "Use: value || default"
            }
          end
          
          if line =~ /if\s+.*\.empty\?.*\n.*\.size\s*[<>=]/
            violations << {
              axiom: :ONE_JOB,
              severity: :info,
              file: file,
              line: idx + 1,
              message: "Checking both empty? and size - pick one",
              fix: "Use either empty? or size comparison, not both"
            }
          end
          
          if line =~ /def\s+(\w+).*\n.*raise.*NotImplementedError/
            violations << {
              axiom: :FAIL_VISIBLY,
              severity: :warn,
              file: file,
              line: idx + 1,
              message: "Method defined but raises NotImplementedError",
              fix: "Remove method or implement it"
            }
          end
          
          if line =~ /TODO|FIXME|HACK|XXX/
            violations << {
              axiom: :PRUNE,
              severity: :info,
              file: file,
              line: idx + 1,
              message: "TODO/FIXME/HACK comment found",
              fix: "Complete the work or remove the comment"
            }
          end
          
          if line =~ /sleep\s*\(\s*[0-9]+\s*\)/ && line =~ /sleep\s*\(\s*([5-9]|\d{2,})\s*\)/
            violations << {
              axiom: :FAIL_VISIBLY,
              severity: :warn,
              file: file,
              line: idx + 1,
              message: "Long sleep (>5s) may indicate poor error handling",
              fix: "Use exponential backoff or proper async"
            }
          end
        end
      end
      violations
    end

    def check_naming_consistency
      violations = []
      
      module_names = {}
      Dir[File.join(lib_path, "**/*.rb")].each do |file|
        content = File.read(file)
        
        content.scan(/module\s+([A-Z]\w+)/) do |match|
          name = match[0]
          module_names[name] ||= []
          module_names[name] << file
        end
        
        content.scan(/class\s+([A-Z]\w+)/) do |match|
          name = match[0]
          module_names[name] ||= []
          module_names[name] << file
        end
      end
      
      module_names.each do |name, files|
        if files.size > 1
          violations << {
            axiom: :ONE_SOURCE,
            severity: :error,
            file: files.join(", "),
            message: "Module/Class '#{name}' defined in #{files.size} files",
            fix: "Consolidate into single file"
          }
        end
      end
      
      Dir[File.join(lib_path, "*.rb")].each do |file|
        basename = File.basename(file, ".rb")
        content = File.read(file)
        
        expected_module = basename.split('_').map(&:capitalize).join
        
        unless content =~ /module\s+#{expected_module}\b|class\s+#{expected_module}\b/i
          violations << {
            axiom: :SELF_EXPLAINING,
            severity: :info,
            file: file,
            message: "Filename '#{basename}' doesn't match module/class name",
            fix: "Rename file or module to match"
          }
        end
      end
      
      violations
    end

    def check_duplicated_logic
      violations = []
      
      code_blocks = {}
      Dir[File.join(lib_path, "**/*.rb")].each do |file|
        content = File.read(file)
        lines = content.lines
        
        lines.each_cons(5).with_index do |block, idx|
          normalized = block.map(&:strip).join("\n")
          next if normalized.length < 50
          next if normalized =~ /^\s*$|^\s*#/
          
          code_blocks[normalized] ||= []
          code_blocks[normalized] << { file: file, line: idx + 1 }
        end
      end
      
      code_blocks.each do |code, locations|
        if locations.size > 1
          violations << {
            axiom: :ONE_SOURCE,
            severity: :warn,
            file: locations.map { |l| "#{l[:file]}:#{l[:line]}" }.join(", "),
            message: "Duplicated 5-line code block found in #{locations.size} places",
            fix: "Extract to shared method"
          }
        end
      end
      
      violations
    end

    def report
      violations = run_all_checks
      return "✓ All axioms enforced (0 violations)" if violations.empty?
      
      grouped = violations.group_by { |v| v[:severity] }
      
      report = []
      report << "Self-Enforcement Report"
      report << "=" * 50
      
      [:error, :warn, :info].each do |severity|
        next unless grouped[severity]
        
        report << ""
        report << "#{severity.upcase} (#{grouped[severity].size}):"
        grouped[severity].each do |v|
          report << "  [#{v[:axiom]}] #{v[:file] || 'lib/'}:#{v[:line]}"
          report << "    #{v[:message]}"
          report << "    → #{v[:fix]}" if v[:fix]
        end
      end
      
      report.join("\n")
    end
  end
end
