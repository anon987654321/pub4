# frozen_string_literal: true

module MASTER
  # SessionCapture - Automatic pattern extraction from successful sessions
  # Ported from MASTER v1 master.yml v49.75 meta_analysis section
  module SessionCapture
    extend self

    QUESTIONS = [
      {
        question: "What new techniques were discovered?",
        action: "Add to structural_analysis or principles",
        category: :technique
      },
      {
        question: "What patterns kept recurring?",
        action: "Codify as detection rules",
        category: :pattern
      },
      {
        question: "What questions yielded good results?",
        action: "Add to hierarchy questions for reuse",
        category: :question
      },
      {
        question: "What manual steps could be automated?",
        action: "Add as new command or automation",
        category: :automation
      },
      {
        question: "What external tools/APIs were useful?",
        action: "Add to providers/integrations",
        category: :tool
      }
    ].freeze

    def capture_file
      File.join(Paths.var, "session_captures.jsonl")
    end

    # Run session capture (call after successful work session)
    def capture(session_id: nil)
      session_id ||= Session.current.id
      
      puts UI.bold("\n📚 Session Capture")
      puts UI.dim("Extracting patterns from this session...\n")

      answers = {}
      
      QUESTIONS.each do |q|
        puts UI.yellow("\n#{q[:question]}")
        puts UI.dim("  Action: #{q[:action]}")
        print "  Answer (or skip): "
        
        answer = $stdin.gets&.chomp&.strip
        next if answer.nil? || answer.empty? || answer.downcase == 'skip'
        
        answers[q[:category]] = answer
      end

      if answers.empty?
        puts UI.dim("\nNo insights captured")
        return Result.ok(captured: false)
      end

      # Save capture
      capture_entry = {
        session_id: session_id,
        timestamp: Time.now.utc.iso8601,
        answers: answers
      }

      File.open(capture_file, "a") do |f|
        f.puts(JSON.generate(capture_entry))
      end

      # Add to learnings automatically
      answers.each do |category, answer|
        learning_category = map_to_learning_category(category)
        if learning_category
          Learnings.record(
            category: learning_category,
            pattern: nil,
            description: answer,
            severity: :info
          )
        end
      end

      puts UI.green("\n✓ Session insights captured and added to learnings")
      
      Result.ok(captured: true, insights: answers.size)
    end

    # Auto-capture if session was successful (called on exit)
    def auto_capture_if_successful
      session = Session.current
      return unless session
      return unless session.metadata_value(:successful)

      puts UI.dim("\n[Auto-capture triggered for successful session]")
      capture(session_id: session.id)
    end

    # Review all captures
    def review
      return Result.err("No captures found") unless File.exist?(capture_file)

      captures = File.readlines(capture_file).map do |line|
        JSON.parse(line, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end.compact

      Result.ok(captures: captures, count: captures.size)
    end

    # Suggest new commands/features based on automation captures
    def suggest_automations
      review_result = review
      return Result.err("No captures to analyze") unless review_result.ok?

      captures = review_result.value[:captures]
      automation_suggestions = captures
        .select { |c| c[:answers][:automation] }
        .map { |c| c[:answers][:automation] }

      Result.ok(suggestions: automation_suggestions)
    end

    private

    def map_to_learning_category(capture_category)
      case capture_category
      when :technique then :good_practice
      when :pattern then :bug_pattern
      when :question then :ux_insight
      when :automation then :architecture
      when :tool then :architecture
      else nil
      end
    end
  end
end
