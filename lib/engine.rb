require 'parser/current'
require 'unparser'
require 'diffy'

module MASTER
  class Engine
    def initialize
      @llm = LLM.new
      @parser = Parser::Multi.new
    end

    def refactor(code, language = 'ruby')
      ast = @parser.parse(code, language)(code)
      analysis = @llm.analyze(ast, language)
      
      if analysis[:risk] == 'low'
        transformed_ast = apply_transforms(ast, analysis[:suggestions])
        transformed_code = Unparser.unparse(transformed_ast)
        { success: true, code: transformed_code, diff: Diffy::Diff.new(code, transformed_code).to_s(:text), analysis: analysis }
      else
        { success: false, suggestions: analysis[:suggestions], error: analysis[:error] }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def analyze(code, language = 'ruby')
      ast = @parser.parse(code, language)(code)
      @llm.analyze(ast, language)
    end

    private

    def apply_transforms(ast, suggestions)
      suggestions.each do |suggestion|
        case suggestion[:type]
        when 'extract_method'
          ast = extract_method(ast, suggestion[:range])
        when 'rename'
          ast = rename_variable(ast, suggestion[:old], suggestion[:new])
        when 'inline'
          ast = inline_variable(ast, suggestion[:var])
        end
      end
      ast
    end

    def extract_method(ast, range)
      # Simplified AST manipulation - expand with real node rewriting
      ast.children[range[0]] = s(:def, s(:sym, :extracted), s(:begin, ast.children[range[1]]))
      ast
    end

    def rename_variable(ast, old, new)
      # Traverse and replace
      ast
    end

    def inline_variable(ast, var)
      # Inline logic
      ast
    end
  end
end

    def refactor(code, language = 'ruby')
      return { success: false, error: 'File too large' } if code.length > 10000
      
      # Offline mode fallback
      if !@api_key || ENV['OFFLINE']
        analysis = { risk: 'low', suggestions: [{ type: 'rename', old: 'old_var', new: 'new_var' }] }
      else
        analysis = @llm.analyze(ast, language)
      end
      
      # Retry on error
      3.times do
        begin
          # ... rest
          break
        rescue => e
          puts "Retry: #{e}"
          sleep 1
        end
      end
    end
    autonomy = Autonomy.new
    decision = autonomy.decide(:refactor, analysis[:risk])
    case decision
    when :apply
      # Apply
    when :preview
      { success: false, preview: transformed_code }
    when :ask
      { success: false, suggestions: analysis[:suggestions] }
    end
    autonomy = Autonomy.new
    decision = autonomy.decide(:refactor, analysis[:risk])
    case decision
    when :apply
      # Apply
    when :preview
      { success: false, preview: transformed_code }
    when :ask
      { success: false, suggestions: analysis[:suggestions] }
    end
