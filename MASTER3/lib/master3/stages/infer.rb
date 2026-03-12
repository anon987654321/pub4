# frozen_string_literal: true

module Master3
  module Stages
    # Infer — natural language to command mapping.
    #
    # Sits between Intake and Route. When intent is :llm, checks whether the
    # message is a natural-language command invocation and promotes it to
    # :command intent. Users never need to learn slash syntax.
    #
    # Pattern order matters: more specific patterns first.
    class Infer
      PATTERNS = [
        # sweep — full codebase refactor
        [ /\b(?:sweep|refactor|clean\s*up|rewrite|polish|tidy\s*up|improve|overhaul)
           (?:\s+(?:all|every(?:thing)?|the))?
           (?:\s+([\w\/.]+))?/ix,
          "sweep" ],

        # autoloop — violation fix cycle
        [ /\b(?:autoloop|fix\s+all\s+violations?|keep\s+fix|loop\s+until|
             iterate\s+until|run\s+until\s+clean|keep\s+going\s+until|
             run\s+(?:it\s+)?(?:again\s+)?until\s+(?:done|clean|fixed))
           (?:\s+(\d+))?/ix,
          "autoloop" ],

        # council — multi-persona deliberation
        [ /\b(?:council|deliberat|multiple\s+perspect|second\s+opinion|
             peer\s+review|debate\s+this|get\s+(?:another|a\s+second)\s+view|
             multi(?:ple)?\s+(?:view|agent|model))\b/ix,
          "council" ],

        # tokens — context size
        [ /\b(?:token\s*count|how\s+many\s+tokens?|context\s+size|
             token\s+usage|how\s+much\s+context)\b/ix,
          "tokens" ],

        # cost — spending
        [ /\b(?:how\s+much\s+(?:has\s+this\s+cost|is\s+this|did\s+this)|
             (?:current\s+)?(?:spend|cost|budget)|what(?:'s|\s+is)\s+the\s+cost)\b/ix,
          "cost" ],

        # undo
        [ /\b(?:undo\s+that|revert\s+(?:that|last|it)|go\s+back|
             take\s+that\s+back|undo\s+(?:last|the\s+last))\b/ix,
          "undo" ],

        # clear — reset context
        [ /\b(?:clear\s+(?:context|chat|history|session|screen)|
             start\s+(?:over|fresh|again)|reset\s+(?:context|session)|
             fresh\s+start|wipe\s+(?:context|history))\b/ix,
          "clear" ],

        # save
        [ /\b(?:save\s+(?:session|this|my\s+work|progress)|
             checkpoint\s+(?:this|session|now))\b/ix,
          "save" ],

        # model info
        [ /\b(?:which\s+model|current\s+model|what\s+model\s+are\s+you|
             what\s+(?:llm|ai|model)\s+(?:are\s+you\s+using|is\s+this))\b/ix,
          "model" ],

        # dmesg — logs
        [ /\b(?:show\s+(?:logs?|events?|history)|system\s+log|dmesg|
             what\s+(?:happened|has\s+happened)|event\s+log|recent\s+activity)\b/ix,
          "dmesg" ],
      ].freeze

      def call(ctx)
        return Result.ok(ctx) unless ctx[:intent] == :llm

        msg = ctx[:message].to_s.strip

        PATTERNS.each do |pattern, cmd|
          next unless (m = msg.match(pattern))

          args = extract_args(cmd, m, msg)
          return Result.ok(ctx.merge(intent: :command, command: cmd, args:))
        end

        Result.ok(ctx)
      end

      private

      def extract_args(cmd, match, msg)
        case cmd
        when "sweep"
          # Capture explicit path: "clean up lib/" or "refactor DEPLOY/rails"
          path = match[1]&.strip
          path = nil if path&.match?(/\A(?:all|everything|the|code|codebase)\z/i)
          path.to_s
        when "autoloop"
          # Capture cycle count: "loop until clean 8 times"
          n = match[1] || msg[/\b(\d+)\s*(?:time|cycle|iteration|loop)/i, 1]
          n.to_s
        when "council"
          # "enable/disable council" or "council on/off"
          if msg.match?(/\b(?:off|disable|stop|turn\s+off)\b/i)
            "off"
          else
            "on"
          end
        else
          ""
        end
      end
    end
  end
end
