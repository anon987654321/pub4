module MASTER
  module UniversalEnforce
    extend self

    def enforce_on_code(code:, language: :ruby, path: nil)
      violations = []
      
      case language
      when :ruby
        violations += check_ruby_axioms(code, path)
      when :javascript, :js
        violations += check_javascript_axioms(code, path)
      when :python
        violations += check_python_axioms(code, path)
      else
        violations += check_universal_axioms(code, path)
      end
      
      Result.ok(violations: violations, auto_fixed: [], code: code)
    end

    def check_ruby_axioms(code, path = nil)
      violations = []
      lines = code.lines
      
      violations += check_bare_rescues(lines, path)
      violations += check_logic_patterns(lines, path)
      violations += check_naming_conventions(lines, path)
      violations += check_method_complexity(lines, path)
      violations += check_code_smells(lines, path)
      violations += check_duplicated_code(lines, path)
      
      violations
    end

    def check_javascript_axioms(code, path = nil)
      violations = []
      lines = code.lines
      
      violations += check_js_var_declarations(lines, path)
      violations += check_js_equality(lines, path)
      violations += check_js_promises(lines, path)
      
      violations
    end

    def check_python_axioms(code, path = nil)
      violations = []
      lines = code.lines
      
      violations += check_python_exceptions(lines, path)
      violations += check_python_imports(lines, path)
      
      violations
    end

    def check_universal_axioms(code, path = nil)
      violations = []
      lines = code.lines
      
      violations += check_line_length(lines, path)
      violations += check_nested_depth(lines, path)
      violations += check_magic_numbers(lines, path)
      
      violations
    end

    private

    def check_bare_rescues(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /rescue\s*$|rescue\s*;|rescue\s*=>/ && line !~ /rescue\s+\w+Error/
          violations << {
            axiom: :FAIL_VISIBLY,
            severity: :error,
            path: path,
            line: idx + 1,
            message: "Bare rescue without error class",
            fix: "rescue StandardError => e"
          }
        end
      end
      violations
    end

    def check_logic_patterns(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /if\s+(.+)\s*$/
          condition = $1.strip
          
          if condition =~ /&&.*\|\|/ && !(condition =~ /\(.*\)/)
            violations << {
              axiom: :SIMPLEST_WORKS,
              severity: :warn,
              path: path,
              line: idx + 1,
              message: "Mixed && and || without parentheses",
              fix: "Add parentheses: (a && b) || c"
            }
          end
          
          if condition =~ /\s==\s*true\b|\s==\s*false\b/
            violations << {
              axiom: :BE_CONCISE,
              severity: :info,
              path: path,
              line: idx + 1,
              message: "Comparing to true/false is redundant",
              fix: "Use 'if variable' directly"
            }
          end
          
          if condition =~ /!\s*!\s*/
            violations << {
              axiom: :SELF_EXPLAINING,
              severity: :info,
              path: path,
              line: idx + 1,
              message: "Double negation (!!) is unclear",
              fix: "Convert to explicit boolean"
            }
          end
        end
        
        if line =~ /return\s+if\b/ && idx > 0 && lines[idx - 1] =~ /return\b/
          violations << {
            axiom: :SIMPLEST_WORKS,
            severity: :warn,
            path: path,
            line: idx + 1,
            message: "Consecutive returns - second may be unreachable",
            fix: "Review control flow"
          }
        end
      end
      violations
    end

    def check_naming_conventions(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /def\s+([a-z_]+)/
          method_name = $1
          
          if method_name.length > 30
            violations << {
              axiom: :BE_CONCISE,
              severity: :warn,
              path: path,
              line: idx + 1,
              message: "Method name too long (#{method_name.length} chars)",
              fix: "Shorten to <30 characters"
            }
          end
          
          if method_name =~ /^(get|set)_/
            violations << {
              axiom: :SELF_EXPLAINING,
              severity: :info,
              path: path,
              line: idx + 1,
              message: "Method name starts with get/set (redundant)",
              fix: "Use noun: '#{method_name.sub(/^(get|set)_/, '')}'"
            }
          end
        end
        
        if line =~ /(class|module)\s+([A-Z]\w+)/
          name = $2
          if name =~ /Helper$|Wrapper$|Bridge$|Utils?$/
            violations << {
              axiom: :BE_CONCISE,
              severity: :warn,
              path: path,
              line: idx + 1,
              message: "Class/module name ends with forbidden suffix",
              fix: "Name what it IS, not what it DOES"
            }
          end
        end
      end
      violations
    end

    def check_method_complexity(lines, path)
      violations = []
      in_method = false
      method_start = 0
      method_name = nil
      nesting_level = 0
      
      lines.each_with_index do |line, idx|
        if line =~ /def\s+(\w+)/
          in_method = true
          method_start = idx
          method_name = $1
          nesting_level = 0
        elsif in_method
          nesting_level += 1 if line =~ /\b(if|unless|while|until|for|case)\b/
          nesting_level -= 1 if line =~ /\bend\b/
          
          if nesting_level > 3
            violations << {
              axiom: :SIMPLEST_WORKS,
              severity: :warn,
              path: path,
              line: idx + 1,
              message: "Nesting level #{nesting_level} (max 3)",
              fix: "Extract nested logic to separate methods"
            }
          end
          
          if line =~ /^\s*end\s*$/ && nesting_level <= 0
            method_lines = idx - method_start + 1
            if method_lines > 25
              violations << {
                axiom: :ONE_JOB,
                severity: :warn,
                path: path,
                line: method_start + 1,
                message: "Method '#{method_name}' is #{method_lines} lines (max 25)",
                fix: "Split into smaller methods"
              }
            end
            in_method = false
          end
        end
      end
      violations
    end

    def check_code_smells(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /\.nil\?\s*\?\s*/
          violations << {
            axiom: :BE_CONCISE,
            severity: :info,
            path: path,
            line: idx + 1,
            message: "Ternary for nil check can use ||",
            fix: "value || default"
          }
        end
        
        if line =~ /TODO|FIXME|HACK|XXX/
          violations << {
            axiom: :PRUNE,
            severity: :info,
            path: path,
            line: idx + 1,
            message: "TODO/FIXME found",
            fix: "Complete the work"
          }
        end
        
        if line =~ /sleep\s*\(\s*([5-9]|\d{2,})\s*\)/
          violations << {
            axiom: :FAIL_VISIBLY,
            severity: :warn,
            path: path,
            line: idx + 1,
            message: "Long sleep (>5s)",
            fix: "Use exponential backoff"
          }
        end
        
        if line =~ /puts\s+|print\s+|p\s+/ && path !~ /test|spec/
          violations << {
            axiom: :FAIL_VISIBLY,
            severity: :info,
            path: path,
            line: idx + 1,
            message: "Debug output (puts/print/p) in production code",
            fix: "Use proper logging"
          }
        end
      end
      violations
    end

    def check_duplicated_code(lines, path)
      violations = []
      lines.each_cons(5).with_index do |block, idx|
        normalized = block.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }.join("\n")
        next if normalized.length < 50
        
        if @seen_blocks ||= {}
        if @seen_blocks[normalized]
          violations << {
            axiom: :ONE_SOURCE,
            severity: :warn,
            path: path,
            line: idx + 1,
            message: "Duplicated 5-line block",
            fix: "Extract to method"
          }
        else
          @seen_blocks[normalized] = { path: path, line: idx + 1 }
        end
        end
      end
      violations
    end

    def check_line_length(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line.length > 120
          violations << {
            axiom: :REFLOW,
            severity: :info,
            path: path,
            line: idx + 1,
            message: "Line too long (#{line.length} chars, max 120)",
            fix: "Break into multiple lines"
          }
        end
      end
      violations
    end

    def check_nested_depth(lines, path)
      violations = []
      depth = 0
      lines.each_with_index do |line, idx|
        depth += 1 if line =~ /\b(if|unless|while|for|def|class|module|begin)\b/
        depth -= 1 if line =~ /\bend\b/
        
        if depth > 4
          violations << {
            axiom: :SIMPLEST_WORKS,
            severity: :error,
            path: path,
            line: idx + 1,
            message: "Nesting depth #{depth} (max 4)",
            fix: "Extract to methods"
          }
        end
      end
      violations
    end

    def check_magic_numbers(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        next if line =~ /^\s*#|^\s*$/
        
        if line =~ /[^0-9a-zA-Z_]((?:[2-9]|\d{2,}))(?![0-9])/
          number = $1
          next if number == "10" || number == "100" || number == "1000"
          
          violations << {
            axiom: :SELF_EXPLAINING,
            severity: :info,
            path: path,
            line: idx + 1,
            message: "Magic number '#{number}' without constant",
            fix: "Extract to named constant"
          }
        end
      end
      violations
    end

    def check_js_var_declarations(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /\bvar\s+/
          violations << {
            axiom: :EXTEND_DONT_MODIFY,
            severity: :warn,
            path: path,
            line: idx + 1,
            message: "Use 'const' or 'let' instead of 'var'",
            fix: "Replace with const/let"
          }
        end
      end
      violations
    end

    def check_js_equality(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /[^=!]==[^=]|[^!]!=[^=]/
          violations << {
            axiom: :FAIL_VISIBLY,
            severity: :warn,
            path: path,
            line: idx + 1,
            message: "Use === or !== for strict equality",
            fix: "Replace == with ==="
          }
        end
      end
      violations
    end

    def check_js_promises(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /\.then\(.*\.then\(/
          violations << {
            axiom: :SIMPLEST_WORKS,
            severity: :info,
            path: path,
            line: idx + 1,
            message: "Nested .then() - consider async/await",
            fix: "Use async/await syntax"
          }
        end
      end
      violations
    end

    def check_python_exceptions(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /except\s*:/
          violations << {
            axiom: :FAIL_VISIBLY,
            severity: :error,
            path: path,
            line: idx + 1,
            message: "Bare except without exception type",
            fix: "except Exception as e:"
          }
        end
      end
      violations
    end

    def check_python_imports(lines, path)
      violations = []
      lines.each_with_index do |line, idx|
        if line =~ /from .+ import \*/
          violations << {
            axiom: :SMALL_INTERFACES,
            severity: :warn,
            path: path,
            line: idx + 1,
            message: "Wildcard import pollutes namespace",
            fix: "Import specific names"
          }
        end
      end
      violations
    end
  end
end
