module MASTER
  module Parser
    class Multi
      def parse(code, language)
        case language
        when 'ruby'
          require 'parser/current'
          Parser::CurrentRuby.parse(code)
        when 'javascript'
          { type: 'js_regex', functions: code.scan(/function\s+(\w+)/), code: code }
        when 'python'
          { type: 'py_regex', defs: code.scan(/def\s+(\w+)/), code: code }
        else
          { type: 'raw', code: code }
        end
      end
    end
  end
end
