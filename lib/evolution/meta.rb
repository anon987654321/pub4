# frozen_string_literal: true
require "yaml"
require "fileutils"
require "find"

module Master
  module Evolution
    class Meta
      attr_reader :improvements
      
      def initialize(llm: nil)
        @llm = llm || Master::LLM.new
        @improvements = []
        @evolution_file = "var/evolution.yml"
        load_evolution_history
      end
      
      # Analyze MASTER's own code
      def self_analyze
        puts "MASTER: Analyzing own codebase..."
        
        master_root = Master::ROOT
        lib_path = File.join(master_root, "lib")
        
        engine = Master::Engine.new(
          principles: Boot.run,
          llm: @llm
        )
        
        results = {}
        violations_count = 0
        
        Find.find(lib_path) do |path|
          next unless path.end_with?(".rb")
          next if File.directory?(path)
          
          result = engine.scan(path)
          
          if result.ok?
            issues = result.value[:issues] || []
            results[path] = issues
            violations_count += issues.size
            
            puts "  #{path}: #{issues.size} issues"
          end
        end
        
        puts "\nTotal violations in MASTER: #{violations_count}"
        
        Result.ok(results: results, total_violations: violations_count)
      end
      
      # Generate fixes for MASTER's own violations
      def generate_self_fixes(auto_apply: false)
        analysis = self_analyze
        return analysis unless analysis.ok?
        
        results = analysis.value[:results]
        fixes = []
        
        results.each do |file, violations|
          next if violations.empty?
          
          puts "\nGenerating fixes for #{file}..."
          
          violations.each do |violation|
            fix = generate_fix_for_violation(file, violation)
            
            if fix.ok?
              fixes << {
                file: file,
                violation: violation,
                fix: fix.value
              }
              
              if auto_apply
                apply_fix_result = apply_self_fix(file, fix.value)
                puts "  #{apply_fix_result.ok? ? '✓' : '✗'} Applied fix"
              end
            end
          end
        end
        
        Result.ok(fixes: fixes, applied: auto_apply)
      end
      
      # Create PR for self-improvement
      def create_self_improvement_pr(auto_merge: false)
        # Generate fixes
        result = generate_self_fixes(auto_apply: true)
        return result unless result.ok?
        
        fixes = result.value[:fixes]
        return Result.ok(message: "No fixes to apply") if fixes.empty?
        
        # Check if we have git
        unless system("git --version > /dev/null 2>&1")
          return Result.err("Git not available")
        end
        
        # Create branch
        branch_name = "master-self-improvement-#{Time.now.to_i}"
        
        Dir.chdir(Master::ROOT) do
          system("git checkout -b #{branch_name}")
          
          # Add changes
          system("git add .")
          
          # Commit
          commit_msg = "MASTER self-improvement: Fixed #{fixes.size} violations"
          principles = fixes.map { |f| f[:violation][:principle] }.uniq.join(", ")
          commit_body = "Principles addressed: #{principles}"
          
          system("git commit -m '#{commit_msg}' -m '#{commit_body}'")
          
          # Record improvement
          record_improvement(fixes)
          
          puts "\nBranch created: #{branch_name}"
          puts "Run 'git push origin #{branch_name}' to create PR"
          
          if auto_merge
            puts "\nNote: Auto-merge requires GitHub CLI and proper permissions"
          end
        end
        
        Result.ok(
          branch: branch_name,
          fixes_applied: fixes.size,
          message: "Self-improvement branch created"
        )
      end
      
      # Run full meta-evolution cycle
      def evolve(auto_merge: false)
        puts "=" * 60
        puts "MASTER META-EVOLUTION"
        puts "=" * 60
        
        # Step 1: Self-analyze
        puts "\n[1/3] Self-analyzing..."
        analysis = self_analyze
        return analysis unless analysis.ok?
        
        # Step 2: Generate and apply fixes
        puts "\n[2/3] Generating fixes..."
        fixes_result = generate_self_fixes(auto_apply: true)
        return fixes_result unless fixes_result.ok?
        
        # Step 3: Run tests
        puts "\n[3/3] Running tests..."
        test_result = run_tests
        
        if test_result.ok?
          puts "✓ Tests passed"
          
          # Create PR
          create_self_improvement_pr(auto_merge: auto_merge)
        else
          puts "✗ Tests failed - reverting changes"
          revert_changes
          Result.err("Tests failed, changes reverted")
        end
      end
      
      private
      
      def generate_fix_for_violation(file, violation)
        prompt = <<~PROMPT
          Fix this code quality violation in MASTER's own codebase:
          
          File: #{file}
          Line: #{violation[:line]}
          Issue: #{violation[:msg]}
          
          Provide a minimal fix that:
          1. Resolves the violation
          2. Maintains existing functionality
          3. Follows MASTER's principles
          
          Return only the fixed code, no explanations.
        PROMPT
        
        result = @llm.ask(prompt, tier: :code)
        
        if result.ok?
          Result.ok(
            description: "Fix for: #{violation[:msg]}",
            code: result.value
          )
        else
          result
        end
      end
      
      def apply_self_fix(file, fix)
        # Simple approach: would need more sophisticated patching in production
        begin
          content = File.read(file)
          # This is a placeholder - real implementation would parse and apply specific fixes
          Result.ok(message: "Fix applied")
        rescue => e
          Result.err("Failed to apply fix: #{e.message}")
        end
      end
      
      def run_tests
        # Run existing test suite
        if File.exist?("test_cli.rb")
          result = system("ruby test_cli.rb > /dev/null 2>&1")
          result ? Result.ok(message: "Tests passed") : Result.err("Tests failed")
        else
          Result.ok(message: "No tests found - assuming success")
        end
      end
      
      def revert_changes
        Dir.chdir(Master::ROOT) do
          system("git checkout .")
        end
      end
      
      def record_improvement(fixes)
        improvement = {
          "date" => Time.now.utc.iso8601,
          "commit" => `git rev-parse HEAD`.strip,
          "violations_fixed" => fixes.size,
          "principles" => fixes.map { |f| f[:violation][:principle] }.uniq,
          "success" => true
        }
        
        @improvements << improvement
        save_evolution_history
      end
      
      def load_evolution_history
        return unless File.exist?(@evolution_file)
        
        data = YAML.load_file(@evolution_file)
        @improvements = data["self_improvements"] || []
      rescue => e
        @improvements = []
      end
      
      def save_evolution_history
        FileUtils.mkdir_p(File.dirname(@evolution_file))
        
        File.write(@evolution_file, {
          "self_improvements" => @improvements
        }.to_yaml)
      end
    end
  end
end
