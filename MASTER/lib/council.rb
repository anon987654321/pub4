# frozen_string_literal: true

require 'singleton'

module MASTER
  module Council
    class << self
      MEMBERS = {
        claude: {
          provider: :anthropic,
          model: 'claude-3-5-sonnet-20241022',
          role: :philosopher,
          strengths: [:reasoning, :safety, :nuance]
        },
        grok: {
          provider: :xai,
          model: 'grok-2-1212',
          role: :rebel,
          strengths: [:creativity, :humor, :edge_cases]
        },
        kimi: {
          provider: :moonshot,
          model: 'moonshot-v1-32k',
          role: :analyst,
          strengths: [:structured, :thorough, :chinese_context]
        },
        gemini: {
          provider: :google,
          model: 'gemini-2.0-flash-exp',
          role: :generalist,
          strengths: [:speed, :broad_knowledge, :multimodal]
        }
      }.freeze

      def debate(prompt:, members: [:claude, :grok, :kimi], rounds: 2, store: true)
        echo = EchoChamber.instance
        history = []
        
        puts "🏛️  Council debate: #{members.size} members, #{rounds} rounds"
        
        # Round 1: Independent
        responses = members.map do |m|
          puts "   #{m} thinking..."
          echoes = echo.find_similar(prompt, limit: 3, exclude: m)
          enhanced = echoes.any? ? "#{prompt}\n\nPast insights:\n#{echoes.map{|e| e[:content][0..100]}.join(\n)}" : prompt
          resp = call_llm(m, enhanced)
          history << {member: m, round: 1, content: resp}
          echo.store(content: resp, source: m, prompt: prompt, tags: [:debate, MEMBERS[m][:role]]) if store
          {member: m, response: resp, role: MEMBERS[m][:role]}
        end
        
        # Round 2+: Synthesis
        (2..rounds).each do |r|
          puts "\n🔄 Round #{r}: Synthesis"
          responses = members.map do |m|
            others = responses.reject{|x| x[:member] == m}.map{|o| "#{o[:member]}: #{o[:response]}"}.join(\n\n)
            synthesis = "Original: #{prompt}\n\nOthers said:\n#{others}\n\nYour synthesis:"
            resp = call_llm(m, synthesis)
            history << {member: m, round: r, content: resp}
            echo.store(content: resp, source: m, prompt: prompt, tags: [:synthesis, r]) if store
            {member: m, response: resp, role: MEMBERS[m][:role]}
          end
        end
        
        # Consensus
        consensus_prompt = "Council perspectives:\n#{responses.map{|r| "#{r[:member]}: #{r[:response]}"}.join(\n\n)}\n\nProvide JSON: {\"synthesis\": \"...\", \"confidence\": 0.85}"
        consensus_raw = MASTER::LLM.call(consensus_prompt, model: 'smart')
        
        consensus = begin
          JSON.parse(consensus_raw.match(/\{.*\}/m)[0], symbolize_names: true)
        rescue
          {synthesis: consensus_raw, confidence: 0.7}
        end
        
        echo.store(content: consensus[:synthesis], source: :consensus, prompt: prompt, tags: [:consensus], strength: consensus[:confidence]) if store && consensus[:confidence] > 0.75
        
        {consensus: consensus, perspectives: responses, history: history, echo_size: echo.size}
      end
      
      def quick_check(prompt:, members: [:claude, :grok])
        debate(prompt: prompt, members: members, rounds: 1, store: false)
      end
      
      def dream_session(topic:, duration_minutes: 10)
        start = Time.now
        reflections = []
        
        puts "💭 Dream session: #{topic} (#{duration_minutes}m)"
        
        iteration = 0
        while Time.now - start < duration_minutes * 60
          iteration += 1
          members = MEMBERS.keys.sample(2)
          prompt = reflections.empty? ? "Explore #{topic} from unexpected angle" : "Building on: #{reflections.last[:insight][0..80]}... Next layer?"
          
          puts "   [#{iteration}] #{members.join(' + ')}"
          result = debate(prompt: prompt, members: members, rounds: 1, store: true)
          reflections << {iteration: iteration, members: members, insight: result[:consensus][:synthesis]}
          
          sleep 30
        end
        
        puts "✅ Dream complete: #{reflections.size} insights"
        {topic: topic, duration: Time.now - start, iterations: reflections.size, reflections: reflections}
      end
      
      def emergency_consult(prompt:, previous_attempts:)
        puts "🚨 Emergency consult (low confidence)"
        context = "Previous attempts:\n#{previous_attempts.map.with_index{|a,i| "#{i+1}: #{a[:response][0..100]}"}.join(\n)}\n\nTask: #{prompt}"
        debate(prompt: context, members: [:claude, :grok, :kimi], rounds: 2, store: true)
      end
      
      private
      
      def call_llm(member, prompt)
        config = MEMBERS[member]
        case config[:provider]
        when :anthropic then MASTER::LLM.anthropic(prompt, model: config[:model])
        when :xai then MASTER::LLM.xai(prompt, model: config[:model])
        when :moonshot then MASTER::LLM.moonshot(prompt, model: config[:model])
        when :google then MASTER::LLM.google(prompt, model: config[:model])
        else MASTER::LLM.call(prompt, model: 'smart')
        end
      rescue => e
        "[Error from #{member}: #{e.message}]"
      end
    end
    
    class EchoChamber
      include Singleton
      
      def initialize
        @storage = []
        @embeddings = {}
      end
      
      def store(content:, source:, prompt:, tags:, strength: 0.7)
        emb = embed(content)
        @storage << {content: content, source: source, prompt: prompt, tags: Array(tags), strength: strength, embedding: emb, timestamp: Time.now}
      end
      
      def find_similar(query, limit: 5, exclude: nil)
        q_emb = embed(query)
        candidates = exclude ? @storage.reject{|s| s[:source] == exclude} : @storage
        
        scored = candidates.map do |item|
          age_days = (Time.now - item[:timestamp]) / 86400.0
          decay = [0.4 ** (age_days / 30.0), 0.1].max
          sim = cosine_sim(q_emb, item[:embedding])
          item.merge(similarity: sim * decay * item[:strength])
        end
        
        scored.sort_by{|x| -x[:similarity]}.take(limit)
      end
      
      def cluster_by_topic(topic)
        relevant = @storage.select{|s| s[:prompt].include?(topic) || s[:content].include?(topic)}
        relevant.group_by{|r| r[:tags].first}.map{|tag, items| {tag: tag, count: items.size, sample: items.first[:content][0..150]}}
      end
      
      def size
        @storage.size
      end
      
      def stats
        {total: @storage.size, by_source: @storage.group_by{|s| s[:source]}.transform_values(&:count)}
      end
      
      private
      
      def embed(text)
        @embeddings[text] ||= begin
          chars = text.downcase.chars.map(&:ord)
          (0..127).map{|i| chars.count(i+32) / [text.length, 1].max.to_f}
        end
      end
      
      def cosine_sim(a, b)
        dot = a.zip(b).map{|x,y| x*y}.sum
        mag_a = Math.sqrt(a.map{|x| x**2}.sum)
        mag_b = Math.sqrt(b.map{|x| x**2}.sum)
        dot / (mag_a * mag_b + 1e-10)
      end
    end
  end
end
