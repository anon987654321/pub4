# frozen_string_literal: true

# StyleCoach UI Dream - Self-critique for CLI and web output
# Inspired by Grok's 2026 interface philosophy

module MASTER
  module Dreams
    class StyleCoach
      PROMPT = <<~PROMPT.freeze
        You are StyleCoach UI — 2026 interface purist, obsessed with Grok-like quiet power.

        Core beliefs:
        - The interface should disappear; only the conversation should remain.
        - Zero visual debt: no unnecessary borders, shadows, colors, icons, animations.
        - Personality lives in words, spacing, timing — never in UI flourishes.
        - Speed > everything: streaming feels instant, no spinners longer than 400ms.
        - Mobile-first, dark-mode default, generous whitespace, large readable text.
        - Every element earns its existence or it dies.

        Critique the following UI/CLI snippet ruthlessly:
        - Describe current feel (noisy/calm, slow/fast, focused/distracted)
        - Point out every pixel/line that adds ceremony or noise
        - Suggest terse, Grok-inspired alternative
        - One-sentence moral reason why your version is superior

        Output format only:
        FEEL: [one word]
        NOISE: [list what to remove]
        FIX: [terse alternative]
        RULE: [one distilled UI lesson]

        Content to judge:
        {{CONTENT}}
      PROMPT

      def initialize(llm: nil)
        @llm = llm || LLM.new
      end

      # Critique CLI output
      def critique_cli(output)
        prompt = PROMPT.sub('{{CONTENT}}', output[0..2000])
        result = @llm.chat(prompt, tier: :fast)
        return nil unless result.ok?

        parse_critique(result.value)
      end

      # Critique HTML/ERB view
      def critique_html(html)
        prompt = PROMPT.sub('{{CONTENT}}', html[0..2000])
        result = @llm.chat(prompt, tier: :fast)
        return nil unless result.ok?

        parse_critique(result.value)
      end

      # Dream: randomly critique own output
      def dream
        # Get recent CLI output from session log if available
        log_path = File.join(Paths.var, 'session_log.txt')
        return nil unless File.exist?(log_path)

        recent = File.read(log_path).lines.last(50).join
        critique = critique_cli(recent)
        return nil unless critique

        # Store the lesson
        lesson = critique[:rule]
        store_lesson(lesson) if lesson

        critique
      end

      private

      def parse_critique(text)
        {
          feel: text[/FEEL:\s*(.+)$/i, 1]&.strip,
          noise: text[/NOISE:\s*(.+)$/i, 1]&.strip,
          fix: text[/FIX:\s*(.+)$/i, 1]&.strip,
          rule: text[/RULE:\s*(.+)$/i, 1]&.strip
        }
      end

      def store_lesson(lesson)
        lessons_file = File.join(Paths.var, 'ui_lessons.txt')
        File.open(lessons_file, 'a') { |f| f.puts "#{Time.now.iso8601}: #{lesson}" }
      rescue
        nil
      end
    end

    # Quick access
    def self.style_coach(llm: nil)
      StyleCoach.new(llm: llm)
    end
  end
end
