# frozen_string_literal: true

module Master
  module Stages
    # Infer — promote natural-language messages to :command intent.
    #
    # Runs after Intake. When intent is :llm, matches the message against
    # known patterns (English and Norwegian) and sets intent :command.
    # Users never need slash syntax.
    class Infer
      PATTERNS = [
        # sweep / refactor
        [ /\b(?:sweep|refactor|clean\s*up|rewrite|polish|tidy\s*up|overhaul|
               improve\s+(?:all|every)|go\s+through\s+(?:all|every)|
               full\s+pass\s+(?:over|on))
           (?:\s+(?:all|every(?:thing)?|the))?
           (?:\s+([\w\/.]+))?/ix,                                      "sweep"    ],

        [ /\b(?:rydd\s+opp|refaktorer|forbedre?|gjennomg[åa]|omskriv)
           (?:\s+([\w\/.]+))?/ix,                                      "sweep"    ],

        # autoloop
        [ /\b(?:autoloop|autofix|fix\s+all\s+violations?|keep\s+(?:fix|loop)|
               loop\s+until|iterate\s+until|run\s+until\s+clean|
               keep\s+going\s+until|(?:run|go)\s+(?:it\s+)?(?:again\s+)?
               until\s+(?:done|clean|fixed|perfect))
           (?:\s+(\d+))?/ix,                                           "autoloop" ],

        [ /\b(?:fiks?\s+alle?\s+(?:feil|brudd)|fortsett\s+(?:til|inntil)|
               kj[øo]r\s+(?:til\s+)?(?:det\s+er\s+)?(?:rent|bra|ferdig))
           (?:\s+(\d+))?/ix,                                           "autoloop" ],

        # council
        [ /\b(?:council|deliberat|multiple\s+perspect|second\s+opinion|
               peer\s+review|debate\s+this|get\s+(?:another|a\s+second)\s+view|
               multi(?:ple)?\s+(?:view|agent|model|perspect))\b/ix,   "council"  ],

        [ /\b(?:r[åa]dsl[åa]g|bruk\s+(?:flere|multiple)\s+(?:perspektiv|
               synsvinkler?)|diskuter\s+(?:dette|det))\b/ix,           "council"  ],

        # explain
        [ /\b(?:explain\s+(?:your(?:self)?|your\s+architecture|how\s+you\s+work)|
               describe\s+(?:your(?:self)?|your\s+architecture)|
               what\s+are\s+you|how\s+(?:are\s+you\s+built|do\s+you\s+work)|
               show\s+(?:your\s+)?architecture|self[\s-]?map)\b/ix,   "explain"  ],

        # persona
        [ /\b(?:(?:switch|change|set)\s+persona\s+(?:to\s+)?(\w+)|
               persona\s+(\w+)|use\s+(\w+)\s+persona)\b/ix,           "persona"  ],

        # memory
        [ /\b(?:what\s+do\s+you\s+remember(?:\s+about\s+([\w\s]+))?|
               show\s+(?:my\s+)?memor(?:y|ies)|list\s+memor(?:y|ies)|
               recall(?:\s+([\w]+))?|what(?:'s|\s+is)\s+in\s+(?:your\s+)?memory|
               remember\s+([\w]+=.+)|forget\s+([\w_]+))\b/ix,         "memory"   ],

        [ /\b(?:hva\s+husker\s+du(?:\s+om\s+([\w\s]+))?|
               vis\s+(?:min\s+)?hukommelse|husk\s+([\w_]+=.+))\b/ix,  "memory"   ],

        # dreams / memory consolidation
        [ /\b(?:dreams?|consolidate?\s+memor(?:y|ies)|memory\s+consolidat|
               dream\s+mode|promote\s+memor(?:y|ies))\b/ix,           "dreams"   ],

        [ /\b(?:token\s*count|how\s+many\s+tokens?|context\s+size|
               token\s+usage|how\s+much\s+context|
               hvor\s+mange\s+token|token\s*antall)\b/ix,              "tokens"   ],

        # cost
        [ /\b(?:how\s+much\s+(?:has\s+this\s+cost|did\s+this\s+cost)|
               (?:current\s+)?(?:spend|cost|budget)|what(?:'s|\s+is)\s+the\s+cost|
               hva\s+koster?\s+(?:dette|det)|kostnader?)\b/ix,         "cost"     ],

        # undo
        [ /\b(?:undo\s+that|revert\s+(?:that|last|it)|go\s+back|
               take\s+that\s+back|angre\s+det|g[åa]\s+tilbake)\b/ix,  "undo"     ],

        # clear
        [ /\b(?:clear\s+(?:context|chat|history|session|screen)|
               start\s+(?:over|fresh|again)|reset\s+(?:context|session)|
               fresh\s+start|t[øo]m\s+(?:kontekst|historikk)|
               begynn\s+p[åa]\s+nytt)\b/ix,                            "clear"    ],

        # save
        [ /\b(?:save\s+(?:session|this|my\s+work|progress)|checkpoint\s+now|
               lagre\s+(?:session|sesjonen?|arbeid))\b/ix,             "save"     ],

        # model info
        [ /\b(?:which\s+model|current\s+model|what\s+model\s+are\s+you|
               what\s+(?:llm|ai|model)\s+(?:are\s+you\s+using|is\s+this))\b/ix,  "model" ],

        [ /\b(?:scan|lint|check\s+(?:code|violations?)|run\s+scan)(?:\s+(deep))?\b/ix, "scan" ],

        # dmesg
        [ /\b(?:show\s+(?:logs?|events?)|system\s+log|dmesg|
               what\s+(?:happened|has\s+happened)|recent\s+activity)\b/ix,        "dmesg" ],
      ].freeze

      def call(ctx)
        return Result.ok(ctx) unless ctx[:intent] == :llm

        msg = ctx[:message].to_s.strip
        PATTERNS.each do |pattern, cmd|
          next unless (m = msg.match(pattern))

          return Result.ok(ctx.merge(intent: :command, command: cmd, args: extract_args(cmd, m, msg)))
        end

        Result.ok(ctx)
      end

      private

      def extract_args(cmd, match, msg)
        case cmd
        when "sweep"
          path = match[1]&.strip
          path = nil if path&.match?(/\A(?:all|everything|the|code|codebase)\z/i)
          path.to_s
        when "autoloop"
          (match[1] || msg[/\b(\d+)\s*(?:time|cycle|iteration|gang|syklus)/i, 1]).to_s
        when "council"
          msg.match?(/\b(?:off|disable|stop|av|skru\s+av)\b/i) ? "off" : "on"
        when "memory"
          match.captures.compact.first.to_s.strip
        when "dreams"
          match.captures.compact.first&.strip.to_s
        when "persona"
          (match[1] || match[2] || match[3]).to_s.strip
        when "soul"
          msg[/\b(version|changelog|diff|approve|reject|rollback|propose.{0,60})/i].to_s.strip
        when "orders"
          msg.match?(/\blist|show\b/i) ? "list" : ""
        when "scan"
          match[1]&.strip.to_s
        else
          ""
        end
      end
    end
  end
end
