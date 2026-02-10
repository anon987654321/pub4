require 'parser/current'
require 'unparser'
require 'diffy'

module MASTER
  class Engine
    attr_accessor :auto_proceed, :confidence_threshold, :create_checkpoints

    def initialize(options = {})
      @llm = LLM.new
      @parser = Parser::Multi.new
      @tools = Tools::Shell.new
      
      # Auto-proceed options
      @auto_proceed = options[:auto_proceed] || false
      @confidence_threshold = options[:confidence_threshold] || 0.85
      @create_checkpoints = options[:create_checkpoints] || false
    end

    def refactor(code, language = 'ruby')
      return { success: false, error: 'File too large' } if code.length > 10000

      ast = @parser.parse(code, language)
      analysis = @llm.analyze(ast, language)

      # Map risk to confidence (inverse relationship)
      # low risk = high confidence, high risk = low confidence
      confidence = case analysis[:risk]
                   when 'low' then 0.9
                   when 'medium' then 0.7
                   when 'high' then 0.4
                   else analysis[:confidence] || 0.5
                   end
      
      if @auto_proceed
        # Check confidence threshold
        if confidence < @confidence_threshold
          return { 
            success: false, 
            skipped: true,
            reason: "Confidence #{confidence} below threshold #{@confidence_threshold}",
            suggestions: analysis[:suggestions] 
          }
        end
        
        # Auto-apply if confidence is high enough
        decision = :apply
      else
        # Use normal autonomy decision
        autonomy = Autonomy.new
        decision = autonomy.decide(:refactor, analysis[:risk])
      end
      
      case decision
      when :apply
        # Create checkpoint before applying if enabled
        create_checkpoint("Before refactoring #{language} code") if @create_checkpoints
        
        transformed_ast = apply_transforms(ast, analysis[:suggestions], language)
        transformed_code = unparse(transformed_ast, language)
        Monitoring.track_tokens(analysis[:tokens_in] || 0, analysis[:tokens_out] || 0)
        Monitoring.track_cost(analysis[:cost] || 0)
        { 
          success: true, 
          code: transformed_code, 
          diff: Diffy::Diff.new(code, transformed_code).to_s(:text), 
          analysis: analysis,
          confidence: confidence
        }
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

    # Create a git checkpoint before applying changes
    def create_checkpoint(message = "MASTER checkpoint")
      return unless @create_checkpoints
      
      # Check if we're in a git repository
      return unless system('git rev-parse --git-dir > /dev/null 2>&1')
      
      # Sanitize message to prevent command injection
      safe_message = message.gsub(/['"\\]/, '')
      
      # Use system with array to avoid shell injection
      system('git', 'add', '-A')
      system('git', 'commit', '-m', safe_message, err: File::NULL)
    end

    # Rollback to previous checkpoint
    def rollback_checkpoint
      return unless @create_checkpoints
      
      # Check if we're in a git repository
      return unless system('git rev-parse --git-dir > /dev/null 2>&1')
      
      # Use system with array to avoid shell injection
      system('git', 'reset', '--hard', 'HEAD~1', err: File::NULL)
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
