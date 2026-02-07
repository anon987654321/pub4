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
      return { success: false, error: 'File too large' } if code.length > 10000

      ast = @parser.parse(code, language)
      analysis = @llm.analyze(ast, language)

      autonomy = Autonomy.new
      decision = autonomy.decide(:refactor, analysis[:risk])
      
      case decision
      when :apply
        transformed_ast = apply_transforms(ast, analysis[:suggestions])
        transformed_code = unparse(transformed_ast, language)
        { success: true, code: transformed_code, diff: Diffy::Diff.new(code, transformed_code).to_s(:text), analysis: analysis }
      when :preview
        transformed_ast = apply_transforms(ast, analysis[:suggestions])
        transformed_code = unparse(transformed_ast, language)
        { success: false, preview: transformed_code, diff: Diffy::Diff.new(code, transformed_code).to_s(:text) }
      when :ask
        { success: false, suggestions: analysis[:suggestions], error: 'Manual review needed' }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def analyze(code, language = 'ruby')
      ast = @parser.parse(code, language)
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
      ast
    end

    def rename_variable(ast, old, new)
      ast
    end

    def inline_variable(ast, var)
      ast
    end

    def unparse(ast, language)
      case language
      when 'ruby'
        Unparser.unparse(ast)
      else
        ast[:code] || ast.inspect
      end
    end
  end
end
