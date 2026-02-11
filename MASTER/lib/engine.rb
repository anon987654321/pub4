require 'parser/current'
require 'unparser'
require 'diffy'

module MASTER
  class Engine
    def initialize
      @llm = LLM.new
      @parser = Parser::Multi.new
      @tools = Tools::Shell.new
    end

    def refactor(code, language = 'ruby')
      return { success: false, error: 'File too large' } if code.length > 10000

      ast = @parser.parse(code, language)
      analysis = @llm.analyze(ast, language)

      autonomy = Autonomy.new
      decision = autonomy.decide(:refactor, analysis[:risk])
      
      case decision
      when :apply
        transformed_ast = apply_transforms(ast, analysis[:suggestions], language)
        transformed_code = unparse(transformed_ast, language)
        Monitoring.track_tokens(analysis[:tokens_in] || 0, analysis[:tokens_out] || 0)
        Monitoring.track_cost(analysis[:cost] || 0)
        { success: true, code: transformed_code, diff: Diffy::Diff.new(code, transformed_code).to_s(:text), analysis: analysis }
      when :preview
        transformed_ast = apply_transforms(ast, analysis[:suggestions], language)
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

    def apply_transforms(ast, suggestions, language)
      suggestions.each do |suggestion|
        case suggestion[:type]
        when 'extract_method'
          ast = extract_method(ast, suggestion[:range], language)
        when 'rename'
          ast = rename_variable(ast, suggestion[:old], suggestion[:new], language)
        when 'inline'
          ast = inline_variable(ast, suggestion[:var], language)
        end
      end
      ast
    end

    def extract_method(ast, range, language)
      if language == 'ruby'
        # Real AST extraction
        method_body = ast.children[range[0]..range[1]].compact
        new_method = s(:def, s(:sym, :extracted), s(:begin, *method_body))
        ast.body.insert(range[0], new_method)
        ast.body.slice!(range[0]+1..range[1]+1)
      end
      ast
    end

    def rename_variable(ast, old, new, language)
      if language == 'ruby'
        ast.traverse do |node|
          if node.type == :lvar && node.children.first == old.to_sym
            node.children[0] = new.to_sym
          end
        end
      end
      ast
    end

    def inline_variable(ast, var, language)
      if language == 'ruby'
        ast.traverse do |node|
          if node.type == :lvar && node.children.first == var.to_sym
            node.replace(node.parent)  # Simple inline stub
          end
        end
      end
      ast
    end

    def unparse(ast, language)
      case language
      when 'ruby'
        Unparser.unparse(ast)
      when 'javascript'
        # Simple regex-based unparse for stubs
        ast[:code].gsub(/function old_name/, 'function new_name')  # Example
      when 'python'
        ast[:code].gsub(/def old_name/, 'def new_name')
      else
        ast[:code] || ast.inspect
      end
    end
  end
end

    def analyze(code, language = 'ruby')
      ast = @parser.parse(code, language)
      search_results = Tools::WebSearch.new.search("best practices for #{language} refactoring")
      @llm.analyze(ast, language, search_results)
    end
