# frozen_string_literal: true

module Master
  module CLI
    # The deterministic operator grammar handles actions whose meaning is
    # unambiguous without a model; everything else falls through to the agent.
    module OperatorGrammar
      Interpretation = Data.define(:kind, :value)

      GREETING = /\A(?:hi|hello|hey|yo|good (?:morning|afternoon|evening))[\s!.?]*\z/i
      REPEAT = /\A(?:again|repeat)(?:\s+(?:that|it))?[.!?]*\z/i
      REPEAT_AGAIN = /\b(?:do|run)\s+(?:that|it)\s+again\b/i
      FOCUS = /\bfocus\s+(?:mode|on|off)\b|\btoggle\s+focus\b/i
      DIRECT_SHELL_ATOM = /\A(?:pwd|whoami|date|uname(?:\s+-[[:alnum:]-]+)?|ls(?:\s+[[:alnum:]_./~*-]+)*|git\s+(?:status|branch(?:\s+--show-current)?|rev-parse\s+--show-toplevel))\z/i

      module_function

      def parse(input)
        text = input.to_s.strip
        return Interpretation.new(:chitchat, nil) if text.match?(GREETING)
        return Interpretation.new(:repeat, nil) if text.match?(REPEAT) || text.match?(REPEAT_AGAIN)
        return Interpretation.new(:toggle_focus, nil) if text.match?(FOCUS)
        return Interpretation.new(:direct_shell, text) if direct_shell?(text)
        nil
      end

      def direct_shell?(command)
        command.to_s.split(/\s+(?:&&|;)\s+/).all? { |part| DIRECT_SHELL_ATOM.match?(part) }
      end
    end
  end
end
