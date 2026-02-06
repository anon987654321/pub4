# frozen_string_literal: true

module MASTER
  module Dreams
    # SocialDreamer - generates viral content ideas, analyzes trends
    class SocialDreamer
      PLATFORMS = %w[twitter instagram tiktok linkedin youtube reddit hackernews].freeze

      VIRAL_PROMPT = <<~PROMPT.freeze
        You are a viral content strategist for 2026. Generate content ideas that:
        - Hook in first 3 words
        - Create emotional response (curiosity, outrage, awe, humor)
        - Are shareable and quotable
        - Fit platform culture perfectly

        Platform: {{PLATFORM}}
        Topic/Niche: {{TOPIC}}
        Tone: {{TONE}}

        Generate 5 viral content ideas. Format:
        1. [HOOK]: First line/caption
           [BODY]: Core content (2-3 sentences max)
           [CTA]: Call to action
           [WHY]: Why it will spread

        Be specific, not generic. No "10 tips" listicles. Think counterintuitive, provocative, or deeply relatable.
      PROMPT

      TREND_PROMPT = <<~PROMPT.freeze
        Analyze this content/topic for viral potential:
        {{CONTENT}}

        Score 1-10 on:
        - Hook strength (grabs attention instantly?)
        - Emotional trigger (makes people feel something?)
        - Shareability (would people tag friends?)
        - Controversy (sparks debate without being offensive?)
        - Timing (relevant now?)

        Overall viral score: X/10
        One-line improvement to maximize spread:
      PROMPT

      def initialize(llm: nil)
        @llm = llm || LLM.new
      end

      # Generate viral content ideas
      def dream(topic:, platform: 'twitter', tone: 'witty')
        prompt = VIRAL_PROMPT
          .sub('{{PLATFORM}}', platform)
          .sub('{{TOPIC}}', topic)
          .sub('{{TONE}}', tone)

        result = @llm.chat(prompt, tier: :strong)
        return nil unless result.ok?

        Dmesg.log("dream0", parent: "social", message: "#{platform}: #{topic[0..30]}") rescue nil
        parse_ideas(result.value)
      end

      # Analyze content for viral potential
      def analyze(content)
        prompt = TREND_PROMPT.sub('{{CONTENT}}', content[0..1000])
        result = @llm.chat(prompt, tier: :fast)
        return nil unless result.ok?

        parse_analysis(result.value)
      end

      # Quick hooks for specific platforms
      def twitter_hook(topic)
        dream(topic: topic, platform: 'twitter', tone: 'provocative')&.first
      end

      def linkedin_hook(topic)
        dream(topic: topic, platform: 'linkedin', tone: 'professional-vulnerable')&.first
      end

      def tiktok_hook(topic)
        dream(topic: topic, platform: 'tiktok', tone: 'chaotic-authentic')&.first
      end

      # Generate controversy (carefully)
      def spicy_take(topic)
        prompt = <<~PROMPT
          Generate a spicy but defensible hot take on: #{topic}
          
          Rules:
          - Contrarian but not offensive
          - Based on logic, not trolling
          - Would make experts debate
          - Tweetable (280 chars max)
          
          Just the take, nothing else.
        PROMPT

        result = @llm.chat(prompt, tier: :fast)
        result.ok? ? result.value.strip : nil
      end

      private

      def parse_ideas(text)
        ideas = []
        current = {}

        text.lines.each do |line|
          case line
          when /\[HOOK\]:\s*(.+)/i
            ideas << current if current[:hook]
            current = { hook: $1.strip }
          when /\[BODY\]:\s*(.+)/i
            current[:body] = $1.strip
          when /\[CTA\]:\s*(.+)/i
            current[:cta] = $1.strip
          when /\[WHY\]:\s*(.+)/i
            current[:why] = $1.strip
          end
        end

        ideas << current if current[:hook]
        ideas
      end

      def parse_analysis(text)
        scores = {}
        text.scan(/(\w+).*?:\s*(\d+)\/10/i) do |name, score|
          scores[name.downcase.to_sym] = score.to_i
        end

        overall = text[/overall.*?(\d+)\/10/i, 1]&.to_i
        improvement = text[/improvement.*?:\s*(.+)$/i, 1]&.strip

        { scores: scores, overall: overall, improvement: improvement }
      end
    end

    def self.social_dreamer(llm: nil)
      SocialDreamer.new(llm: llm)
    end
  end
end
