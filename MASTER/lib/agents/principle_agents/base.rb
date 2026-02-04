# frozen_string_literal: true

module Master
  module Agents
    module PrincipleAgents
      class Base
        attr_reader :principle, :llm, :fixes_applied
        
        def initialize(principle:, llm: nil)
          @principle = principle
          @llm = llm || Master::LLM.new
          @fixes_applied = []
        end
        
        # Scan files for violations of this agent's principle
        def scan(files)
          raise NotImplementedError, "Subclass must implement #scan"
        end
        
        # Suggest refactoring for a violation
        def suggest_refactor(violation)
          raise NotImplementedError, "Subclass must implement #suggest_refactor"
        end
        
        # Apply a fix with optional confirmation
        def apply_fix(file, fix, confirm: true)
          if confirm
            puts "\nProposed fix for #{file}:"
            puts "─" * 60
            puts fix[:description]
            puts "─" * 60
            puts "\nApply this fix? [y/n] "
            
            response = gets&.strip&.downcase
            return Result.err("Fix rejected by user") unless response&.start_with?("y")
          end
          
          # Apply the fix
          begin
            backup_file(file)
            
            if fix[:type] == :replace
              apply_replace_fix(file, fix)
            elsif fix[:type] == :extract
              apply_extract_fix(file, fix)
            else
              return Result.err("Unknown fix type: #{fix[:type]}")
            end
            
            @fixes_applied << {
              file: file,
              fix: fix,
              timestamp: Time.now.utc.iso8601
            }
            
            Result.ok(message: "Fix applied to #{file}")
          rescue => e
            restore_backup(file)
            Result.err("Failed to apply fix: #{e.message}")
          end
        end
        
        # Run agent on files
        def run(files, auto_fix: false)
          violations = scan(files)
          
          puts "#{self.class.name}: Found #{violations.size} violations"
          
          violations.each_with_index do |violation, i|
            puts "\n[#{i + 1}/#{violations.size}] #{violation[:file]}:#{violation[:line]}"
            puts "  #{violation[:description]}"
            
            suggestion = suggest_refactor(violation)
            
            if suggestion.ok?
              fix = suggestion.value
              result = apply_fix(violation[:file], fix, confirm: !auto_fix)
              
              if result.ok?
                puts "  ✓ Fixed"
              else
                puts "  ✗ Not fixed: #{result.error}"
              end
            else
              puts "  ✗ No suggestion: #{suggestion.error}"
            end
          end
          
          Result.ok(
            violations_found: violations.size,
            fixes_applied: @fixes_applied.size
          )
        end
        
        protected
        
        def backup_file(file)
          backup_dir = ".master_backups"
          FileUtils.mkdir_p(backup_dir)
          
          timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
          backup_name = "#{File.basename(file)}.#{timestamp}.bak"
          backup_path = File.join(backup_dir, backup_name)
          
          FileUtils.cp(file, backup_path)
        end
        
        def restore_backup(file)
          backup_dir = ".master_backups"
          backups = Dir.glob(File.join(backup_dir, "#{File.basename(file)}.*.bak"))
          return if backups.empty?
          
          latest_backup = backups.sort.last
          FileUtils.cp(latest_backup, file)
        end
        
        def apply_replace_fix(file, fix)
          content = File.read(file)
          updated = content.gsub(fix[:old_code], fix[:new_code])
          File.write(file, updated)
        end
        
        def apply_extract_fix(file, fix)
          content = File.read(file)
          
          # Insert new method/class
          if fix[:insert_before]
            content = content.sub(fix[:insert_before], "#{fix[:new_code]}\n\n#{fix[:insert_before]}")
          else
            content += "\n\n#{fix[:new_code]}"
          end
          
          # Update call sites
          if fix[:update_calls]
            content = content.gsub(fix[:old_code], fix[:call_code])
          end
          
          File.write(file, content)
        end
      end
    end
  end
end
