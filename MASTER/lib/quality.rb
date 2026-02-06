# frozen_string_literal: true

module MASTER
  # Quality assurance and "Never Lose Again" checklist
  # Implements deletion tracking, test verification, and usability heuristics
  class Quality
    # Nielsen Norman Usability Heuristics
    NIELSEN_HEURISTICS = {
      visibility: 'Visibility of system status',
      match: 'Match between system and real world',
      control: 'User control and freedom',
      consistency: 'Consistency and standards',
      prevention: 'Error prevention',
      recognition: 'Recognition rather than recall',
      flexibility: 'Flexibility and efficiency of use',
      aesthetic: 'Aesthetic and minimalist design',
      recovery: 'Help users recognize, diagnose, recover from errors',
      help: 'Help and documentation'
    }.freeze
    
    def initialize
      @warnings = []
    end
    
    # Check git diff for deletions and verify nothing was lost
    def check_deletions(diff_output = nil)
      diff_output ||= `git --no-pager diff --unified=0`
      
      deleted_lines = diff_output.lines.select { |l| l.start_with?('-') && !l.start_with?('---') }
      return Result.ok({ deleted: 0, lost: [] }) if deleted_lines.empty?
      
      lost_items = []
      
      # Check for deleted functions/methods/classes
      deleted_lines.each do |line|
        content = line[1..-1].strip
        
        # Ruby method definition
        if content =~ /^\s*def\s+(\w+)/
          method_name = $1
          # Check if method still exists anywhere in codebase
          unless method_exists_in_codebase?(method_name)
            lost_items << { type: :method, name: method_name, line: content }
          end
        end
        
        # Ruby class definition
        if content =~ /^\s*class\s+(\w+)/
          class_name = $1
          unless class_exists_in_codebase?(class_name)
            lost_items << { type: :class, name: class_name, line: content }
          end
        end
        
        # Module definition
        if content =~ /^\s*module\s+(\w+)/
          module_name = $1
          unless module_exists_in_codebase?(module_name)
            lost_items << { type: :module, name: module_name, line: content }
          end
        end
      end
      
      if lost_items.any?
        Result.err({
          deleted: deleted_lines.count,
          lost: lost_items,
          message: "#{lost_items.count} items appear to be lost (not moved)"
        })
      else
        Result.ok({
          deleted: deleted_lines.count,
          lost: [],
          message: 'All deleted items were moved elsewhere'
        })
      end
    end
    
    # Count autoload statements before and after
    def check_autoloads(before_dir = nil, after_dir = nil)
      before_dir ||= Paths.lib
      after_dir ||= Paths.lib
      
      before_count = count_autoloads(before_dir)
      after_count = count_autoloads(after_dir)
      
      if after_count < before_count
        delta = before_count - after_count
        @warnings << "Autoload count decreased: #{before_count} → #{after_count} (-#{delta})"
        Result.err("Autoload count decreased by #{delta}")
      else
        Result.ok("Autoloads: #{before_count} → #{after_count}")
      end
    end
    
    # Count test count before and after
    def check_tests(test_dir = nil)
      test_dir ||= File.join(Paths.root, 'test')
      return Result.ok('No test directory') unless File.directory?(test_dir)
      
      before_count = count_test_methods(test_dir, from_git: true)
      after_count = count_test_methods(test_dir)
      
      if after_count < before_count
        delta = before_count - after_count
        @warnings << "Test count decreased: #{before_count} → #{after_count} (-#{delta})"
        Result.err("Test count decreased by #{delta}")
      else
        Result.ok("Tests: #{before_count} → #{after_count}")
      end
    end
    
    # Full "Never Lose Again" checklist before commit
    def pre_commit_check
      results = {}
      
      # 1. Check deletions
      results[:deletions] = check_deletions
      
      # 2. Check autoloads
      results[:autoloads] = check_autoloads
      
      # 3. Check tests
      results[:tests] = check_tests
      
      # 4. Check for TODO/FIXME in diff
      diff = `git --no-pager diff`
      added_todos = diff.lines.count { |l| l.start_with?('+') && l =~ /TODO|FIXME|HACK/ }
      results[:todos] = added_todos > 0 ? 
        Result.err("#{added_todos} new TODO/FIXME/HACK comments") :
        Result.ok('No new technical debt markers')
      
      # Summary
      failures = results.select { |_, v| !v.ok? }
      
      if failures.any?
        puts "\n━━━ Pre-Commit Check FAILED ━━━"
        failures.each do |check, result|
          puts "✗ #{check}: #{result.error}"
        end
        puts "\nRequires explicit approval to proceed."
        Result.err(failures)
      else
        puts "\n━━━ Pre-Commit Check PASSED ━━━"
        results.each do |check, result|
          puts "✓ #{check}: #{result.value}"
        end
        Result.ok(results)
      end
    end
    
    # Check UI code against Nielsen Norman heuristics
    def check_usability(file)
      return Result.ok('Not a UI file') unless ui_related?(file)
      
      code = File.read(file)
      issues = []
      
      # Check for progress indicators (visibility)
      unless code =~ /progress|spinner|loading|status/i
        issues << { heuristic: :visibility, issue: 'No progress indicators found' }
      end
      
      # Check for natural language (match)
      if code =~ /[A-Z_]{5,}/ && code !~ /MASTER|DEFAULT|MAX|MIN|VERSION/
        # Only flag if constant appears to be used as UI text
        issues << { heuristic: :match, issue: 'Unnatural language (ALL_CAPS)' }
      end
      
      # Check for undo/confirmation (control)
      if code =~ /delete|remove|destroy/i && !(code =~ /confirm|undo|revert/)
        issues << { heuristic: :control, issue: 'Destructive action without confirmation' }
      end
      
      # Check for error messages (recovery)
      if code =~ /error|fail|exception/i && !(code =~ /help|hint|suggestion/)
        issues << { heuristic: :recovery, issue: 'Error handling without helpful messages' }
      end
      
      # Check for consistency
      if code.scan(/def\s+(\w+)/).flatten.any? { |m| m =~ /^(get|set|fetch|retrieve)/ }
        methods = code.scan(/def\s+(get_|set_|fetch_|retrieve_)\w+/).flatten
        if methods.uniq.count > 2
          issues << { heuristic: :consistency, issue: 'Inconsistent naming (get/fetch/retrieve)' }
        end
      end
      
      if issues.any?
        Result.err({ file: file, issues: issues })
      else
        Result.ok("UI code follows usability heuristics")
      end
    end
    
    # Run usability checks on all UI-related files
    def audit_usability(target = Paths.lib)
      files = collect_files(target).select { |f| ui_related?(f) }
      
      all_issues = []
      files.each do |file|
        result = check_usability(file)
        all_issues.concat(result.error[:issues]) unless result.ok?
      end
      
      if all_issues.any?
        grouped = all_issues.group_by { |i| i[:heuristic] }
        puts "\n━━━ Usability Issues ━━━"
        grouped.each do |heuristic, issues|
          puts "\n#{NIELSEN_HEURISTICS[heuristic]}:"
          issues.each { |i| puts "  • #{i[:issue]}" }
        end
        Result.err(all_issues)
      else
        Result.ok("All UI code follows usability heuristics")
      end
    end
    
    private
    
    def method_exists_in_codebase?(method_name)
      # Search all Ruby files for method definition
      files = Dir.glob(File.join(Paths.lib, '**', '*.rb'))
      files.any? do |file|
        File.read(file) =~ /def\s+#{Regexp.escape(method_name)}\b/
      end
    rescue
      false
    end
    
    def class_exists_in_codebase?(class_name)
      files = Dir.glob(File.join(Paths.lib, '**', '*.rb'))
      files.any? do |file|
        File.read(file) =~ /class\s+#{Regexp.escape(class_name)}\b/
      end
    rescue
      false
    end
    
    def module_exists_in_codebase?(module_name)
      files = Dir.glob(File.join(Paths.lib, '**', '*.rb'))
      files.any? do |file|
        File.read(file) =~ /module\s+#{Regexp.escape(module_name)}\b/
      end
    rescue
      false
    end
    
    def count_autoloads(dir)
      loader_file = File.join(dir, 'loader.rb')
      return 0 unless File.exist?(loader_file)
      
      content = File.read(loader_file)
      content.scan(/autoload\s+:\w+/).count
    rescue
      0
    end
    
    def count_test_methods(test_dir, from_git: false)
      if from_git
        # Count from previous git commit
        files_output = `git ls-tree -r --name-only HEAD -- #{test_dir} 2>/dev/null`
        return 0 if files_output.empty?
        
        test_files = files_output.lines.map(&:strip).select { |f| f =~ /test_.*\.rb$/ }
        test_files.sum do |file|
          content = `git show HEAD:#{file} 2>/dev/null`
          content.scan(/def\s+test_/).count
        end
      else
        files = Dir.glob(File.join(test_dir, '**', 'test_*.rb'))
        files.sum do |file|
          File.read(file).scan(/def\s+test_/).count
        end
      end
    rescue
      0
    end
    
    def ui_related?(file)
      file =~ /(ui|cli|tty|view|dashboard|interface|prompt|menu)/i
    end
    
    def collect_files(target)
      if File.file?(target)
        [target]
      else
        Dir.glob(File.join(target, '**', '*.rb'))
      end
    end
  end
end
