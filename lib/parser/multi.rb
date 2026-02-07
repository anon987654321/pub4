module MASTER
  module Parser
    class Multi
      def parse(code, language)
        case language
        when 'ruby'
          require 'parser/current'
          Parser::CurrentRuby.parse(code)
        when 'javascript'
          functions = code.scan(/function\s+(\w+)\s*\(/).flatten
          variables = code.scan(/var\s+(\w+)\s*=/).flatten
          { type: 'js', functions: functions, variables: variables, code: code }
        when 'python'
          defs = code.scan(/def\s+(\w+)\s*\(/).flatten
          variables = code.scan(/(\w+)\s*=/).flatten.uniq
          { type: 'py', defs: defs, variables: variables, code: code }
        else
          { type: 'raw', code: code }
        end
      end
    end
  end
end
