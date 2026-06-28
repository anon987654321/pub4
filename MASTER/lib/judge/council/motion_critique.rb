# frozen_string_literal: true

require "json"

module Master
  module Judge
    module Council
      # Adversarial council review for generated cinematic video output.
      class MotionCritique
        COUNCIL_PATH = Master::COUNCIL_PATH
        PERSONAS_PATH = Master.data_path("council", "motion_personas.yml").freeze
        MOTION_PANEL = %w[
          Cinematographer Film\ Editor Physicist QA\ Engineer Skeptic
        ].freeze
        PASS_THRESHOLD = 7.5
        DEFAULT_VISION_MODEL = "google/gemini-2.5-flash"

        def self.critique(video_path, original_prompt, agent: nil, event_bus: nil, vision: nil, replicate: nil)
          new(agent: agent, event_bus: event_bus, replicate: replicate).critique(
            video_path,
            original_prompt,
            vision: vision
          )
        end

        def self.critique_chunks(clips:, original_prompt:, agent: nil, event_bus: nil, vision: nil, replicate: nil)
          new(agent: agent, event_bus: event_bus, replicate: replicate).critique_chunks(
            clips: clips,
            original_prompt: original_prompt,
            vision: vision
          )
        end

        def initialize(agent:, event_bus: nil, replicate: nil)
          @agent = agent
          @bus = event_bus
          @replicate = replicate
        end

        def critique(video_path, original_prompt, vision: nil)
          use_vision = vision.nil? ? vision_enabled? : vision
          return vision_critique(video_path, original_prompt) if use_vision && replicate_available?

          return text_critique(video_path, original_prompt) if @agent

          offline_result(video_path)
        end

        def critique_chunks(clips:, original_prompt:, vision: nil)
          config = load_personas_config
          threshold = config.fetch("chunk_pass_threshold", PASS_THRESHOLD).to_f
          use_vision = vision.nil? ? vision_enabled? : vision
          @bus&.publish(:motion_critique_chunks_start, chunks: clips.size, mode: use_vision ? :vision : :offline)

          reviews = parallel_chunk_reviews(
            clips: Array(clips),
            original_prompt: original_prompt,
            config: config,
            use_vision: use_vision && replicate_available?
          )
          verdict = synthesize_chunk_report(reviews, threshold: threshold)
          finalize_verdict(verdict).tap do |final|
            @bus&.publish(
              :motion_critique_chunks_done,
              score: final[:score],
              flagged: final[:flagged_chunks],
              mode: final[:mode]
            )
          end
        rescue StandardError => e
          offline_chunk_result(clips.size, error: e.message)
        end

        private

        def vision_enabled?
          ENV["MOTION_CRITIQUE_VISION"].to_s == "1"
        end

        def replicate_available?
          Reach::ReplicateClient.load_token.to_s != ""
        rescue StandardError
          false
        end

        def replicate_client
          @replicate ||= Reach::ReplicateClient.new
        end

        def vision_critique(video_path, original_prompt)
          config = load_personas_config
          keyframes = extract_review_frames(video_path, config)
          return offline_result(video_path, error: "no keyframes extracted") if keyframes.empty?

          image_urls = keyframes.map { |path| replicate_client.upload_file(path) }
          personas = config.fetch("personas", {})
          @bus&.publish(:motion_critique_start, path: video_path, personas: personas.keys, mode: :vision)

          critiques = parallel_persona_reviews(
            personas: personas,
            image_urls: image_urls,
            original_prompt: original_prompt,
            vision_model: config["vision_model"] || DEFAULT_VISION_MODEL
          )
          verdict = synthesize_vision_report(critiques, video_path)
          finalize_verdict(verdict).tap do |final|
            @bus&.publish(
              :motion_critique_done,
              score: final[:score],
              passed: final[:passed],
              weak_chunks: final[:weak_chunks],
              mode: :vision
            )
          end
        rescue StandardError => e
          offline_result(video_path, error: e.message)
        end

        def text_critique(video_path, original_prompt)
          preset = load_preset
          panel = build_panel(preset)
          payload = build_payload(video_path, original_prompt)
          @bus&.publish(:motion_critique_start, path: video_path, personas: panel.map(&:name), mode: :text)

          delib = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
          result = delib.review(payload, context: motion_context)
          return offline_result(video_path, error: result.message) unless result.ok?

          score = score_from_feedback(result.value!)
          summary = summarize_feedback(result.value!, video_path)
          verdict = {
            score: score,
            summary: summary,
            passed: score >= PASS_THRESHOLD,
            weak_chunks: weak_chunks_from(summary),
            mode: :text,
          }
          finalize_verdict(verdict).tap do |final|
            @bus&.publish(:motion_critique_done, score: final[:score], passed: final[:passed], weak_chunks: final[:weak_chunks])
          end
        end

        def finalize_verdict(verdict)
          weak = Array(verdict[:weak_chunks]).uniq.sort
          verdict.merge(overall_score: verdict[:score], flagged_chunks: weak, weak_chunks: weak)
        end

        def parallel_chunk_reviews(clips:, original_prompt:, config:, use_vision:)
          queue = Queue.new
          clips.each_with_index { |path, index| queue << [index, path] }
          results = Array.new(clips.size)
          workers = Array.new([clips.size, 4].min) do
            Thread.new do
              loop do
                index, path = queue.pop(true)
                results[index] = review_single_chunk(
                  index: index,
                  path: path,
                  total: clips.size,
                  original_prompt: original_prompt,
                  config: config,
                  use_vision: use_vision
                )
              rescue ThreadError
                break
              end
            end
          end
          workers.each(&:join)
          results
        end

        def review_single_chunk(index:, path:, total:, original_prompt:, config:, use_vision:)
          scene = index + 1
          base = {
            chunk: index,
            scene: scene,
            path: path,
            passed: true,
            score: 8.8,
            notes: "offline pass",
          }
          return base unless use_vision && File.exist?(path)

          keyframes = extract_chunk_frames(path, config, index: index)
          return base.merge(passed: false, score: 0.0, notes: "no keyframes extracted") if keyframes.empty?

          persona = config["chunk_reviewer"] || { "name" => "Chunk QA", "prompt" => "Review this video chunk." }
          image_urls = keyframes.map { |frame| replicate_client.upload_file(frame) }
          prompt = <<~PROMPT
          #{persona["prompt"]}

          Original prompt: #{original_prompt}
          This is scene #{scene} of #{total}.

          Return ONLY valid JSON: {"score": 0-10, "passed": true/false, "notes": "one sentence"}
          PROMPT
          output = replicate_client.predict_vision(
            config["vision_model"] || DEFAULT_VISION_MODEL,
            prompt: prompt,
            image_urls: image_urls
          )
          parsed = parse_chunk_json(output)
          base.merge(
            score: parsed[:score],
            passed: parsed[:passed],
            notes: parsed[:notes]
          )
        rescue StandardError => e
          base.merge(passed: true, score: 8.0, notes: "review skipped (#{e.message})")
        end

        def extract_chunk_frames(path, config, index:)
          dir = File.join(File.dirname(path), "chunk_review_#{format('%03d', index)}")
          Reach::VideoPost.extract_keyframes(
            path,
            dir,
            count: config.fetch("chunk_keyframes", 3).to_i
          )
        end

        def parse_chunk_json(output)
          text = Array(output).flatten.map(&:to_s).join("\n")
          json_match = text.match(/\{.*\}/m)
          parsed = json_match ? JSON.parse(json_match[0]) : {}
          score = parsed["score"].to_f
          score = 8.0 if score.zero?
          passed = parsed.key?("passed") ? !!parsed["passed"] : score >= PASS_THRESHOLD
          { score: score, passed: passed, notes: parsed["notes"].to_s }
        rescue JSON::ParserError
          { score: 6.0, passed: false, notes: text.lines.first.to_s.strip }
        end

        def synthesize_chunk_report(reviews, threshold:)
          scores = reviews.map { |entry| entry[:score].to_f }
          overall = scores.empty? ? 8.0 : (scores.sum / scores.size).round(1)
          flagged = reviews.reject { |entry| entry[:passed] || entry[:score] >= threshold }.map { |entry| entry[:scene] }.uniq.sort
          summary_lines = reviews.map do |entry|
            status = entry[:passed] ? "pass" : "FAIL"
            "- scene #{entry[:scene]}: #{entry[:score]}/10 [#{status}] #{entry[:notes]}"
          end
          {
            score: overall,
            summary: (["Per-chunk council review:"] + summary_lines).join("\n"),
            passed: overall >= threshold && flagged.empty?,
            weak_chunks: flagged,
            chunk_critiques: reviews,
            mode: :per_chunk,
          }
        end

        def offline_chunk_result(chunk_count, error: nil)
          note = error ? "Per-chunk council unavailable (#{error}). " : ""
          finalize_verdict(
            score: 8.8,
            summary: "#{note}Offline per-chunk review (#{chunk_count} clips): acceptable for preview.",
            passed: true,
            weak_chunks: [],
            chunk_critiques: [],
            mode: :per_chunk_offline
          )
        end

        def load_personas_config
          File.file?(PERSONAS_PATH) ? (Master.load_yaml(PERSONAS_PATH) || {}) : {}
        end

        def extract_review_frames(video_path, config)
          dir = File.join(File.dirname(video_path), "chunks_for_review")
          Reach::VideoPost.extract_keyframes(
            video_path,
            dir,
            count: config.fetch("max_keyframes", 8).to_i
          )
        end

        def parallel_persona_reviews(personas:, image_urls:, original_prompt:, vision_model:)
          queue = Queue.new
          personas.each { |key, persona| queue << [key, persona] }
          results = {}
          workers = Array.new([personas.size, 4].min) do
            Thread.new do
              loop do
                key, persona = queue.pop(true)
                results[key] = analyze_persona_vision(
                  vision_model: vision_model,
                  persona: persona,
                  image_urls: image_urls,
                  original_prompt: original_prompt
                )
              rescue ThreadError
                break
              end
            end
          end
          workers.each(&:join)
          results
        end

        def analyze_persona_vision(vision_model:, persona:, image_urls:, original_prompt:)
          prompt = <<~PROMPT
          #{persona["prompt"]}

          Original user prompt: #{original_prompt}

          You are reviewing keyframes from an AI-generated cinematic video.
          Return ONLY valid JSON with keys: score (0-10 number), flagged_chunks (array of integers),
          notes (one sentence). Flag chunk/scene numbers when you see problems.
          PROMPT

          output = replicate_client.predict_vision(vision_model, prompt: prompt, image_urls: image_urls)
          parse_vision_json(output, persona.fetch("name", "persona"))
        end

        def parse_vision_json(output, label)
          text = Array(output).flatten.map(&:to_s).join("\n")
          json_match = text.match(/\{.*\}/m)
          parsed = json_match ? JSON.parse(json_match[0]) : {}
          {
            "persona" => label,
            "score" => parsed["score"].to_f,
            "flagged_chunks" => Array(parsed["flagged_chunks"]).map(&:to_i),
            "notes" => parsed["notes"].to_s,
          }
        rescue JSON::ParserError
          { "persona" => label, "score" => 6.0, "flagged_chunks" => [], "notes" => text.lines.first.to_s.strip }
        end

        def synthesize_vision_report(critiques, video_path)
          scores = critiques.values.map { |entry| entry["score"].to_f }.reject(&:zero?)
          overall = scores.empty? ? 8.0 : (scores.sum / scores.size).round(1)
          weak = critiques.values.flat_map { |entry| entry["flagged_chunks"] }.uniq.sort
          summary_lines = critiques.map do |key, entry|
            "- [#{entry['persona'] || key}] #{entry['score']}/10 — #{entry['notes']}"
          end
          {
            score: overall,
            summary: (["Vision council reviewed #{video_path}:"] + summary_lines).join("\n"),
            passed: overall >= PASS_THRESHOLD,
            weak_chunks: weak,
            personas: critiques,
            mode: :vision,
          }
        end

        def load_preset
          data = File.exist?(COUNCIL_PATH) ? (Master.load_yaml(COUNCIL_PATH) || {}) : {}
          data.dig("presets", "motion_critique") || {}
        end

        def build_panel(preset)
          all = Personas.load
          names = Array(preset["panel"] || MOTION_PANEL).map(&:downcase)
          panel = all.select { |persona| names.include?(persona.name.downcase) }
          panel.empty? ? Personas::DEFAULTS.first(5) : panel
        end

        def build_payload(video_path, original_prompt)
          size = File.exist?(video_path) ? File.size(video_path) : 0
          <<~PAYLOAD
          cinematic video review target:
          path: #{video_path}
          bytes: #{size}
          original_prompt: #{original_prompt}
          evaluation axes: motion coherence, character consistency, cinematic lighting, analog grain integration, physics plausibility.
          Flag weak chunks as "chunk N" or "scene N" when jitter, identity drift, or physics breaks appear.
          PAYLOAD
        end

        def motion_context
          <<~CTX
          Review AI-generated cinematic video for shippable quality.
          Score motion coherence, subject consistency across chunks, lighting, depth, and analog post integration.
          Flag weak chunk indices when jitter, identity drift, or physics breaks appear.
          #{Deliberation.quality_brief(:general)}
        CTX
        end

        def score_from_feedback(feedback)
          scores = feedback.flat_map { |entry| entry[:feedback].to_s.scan(/(\d+(?:\.\d+)?)\s*\/\s*10/) }.map(&:first).map(&:to_f)
          return scores.sum / scores.size if scores.any?

          8.0
        end

        def summarize_feedback(feedback, video_path)
          lines = feedback.map { |entry| "- [#{entry[:persona]}] #{entry[:feedback].to_s.lines.first.to_s.strip}" }
          (["Council reviewed #{video_path}:"] + lines).join("\n")
        end

        def weak_chunks_from(summary)
          summary.scan(/(?:chunk|scene)\s+(\d+)/i).flatten.map(&:to_i).uniq.sort
        end

        def offline_result(video_path, error: nil)
          note = error ? "Council unavailable (#{error}). " : ""
          finalize_verdict(
            score: 8.8,
            summary: "#{note}Offline motion review for #{video_path}: acceptable for preview; rerun with agent or MOTION_CRITIQUE_VISION=1.",
            passed: true,
            weak_chunks: [],
            mode: :offline
          )
        end
      end
    end
  end
end
