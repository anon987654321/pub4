require 'json'

module MASTER
  # Voice - Speech interface for MASTER
  # Provides speech-to-text and text-to-speech capabilities
  class Voice
    attr_reader :listening, :wake_word

    def initialize(options = {})
      @wake_word = options[:wake_word] || "hey master"
      @language = options[:language] || "en-US"
      @voice = options[:voice] || "en-US-Neural2-J"
      @listening = false
      @callback = nil
    end

    # Listen for voice commands
    def self.listen(options = {}, &block)
      voice = new(options)
      voice.listen(&block)
    end

    def listen(&block)
      @callback = block
      @listening = true
      
      puts "🎤 Voice mode activated"
      puts "   Wake word: '#{@wake_word}'"
      puts "   Say '#{@wake_word}' to start, 'exit' to quit"
      puts ""

      # Simulate listening loop
      # In production, this would use actual speech recognition
      loop do
        print "🎤 Listening... "
        input = STDIN.gets
        break if input.nil? # Handle EOF/closed STDIN
        
        input = input.chomp
        break if input.downcase == 'exit'
        
        # Check for wake word
        if input.downcase.include?(@wake_word)
          puts "✓ Wake word detected"
          
          # Get actual command
          print "🎤 Command: "
          command = STDIN.gets
          break if command.nil? # Handle EOF/closed STDIN
          command = command.chomp
          
          if command && !command.empty?
            process_command(command, &block)
          end
        else
          puts "(Wake word not detected - say '#{@wake_word}')"
        end
      end
      
      @listening = false
      puts "👋 Voice mode deactivated"
    end

    # Speak text using text-to-speech
    def self.speak(text, options = {})
      voice = new(options)
      voice.speak(text)
    end

    def speak(text)
      puts "🔊 MASTER: #{text}"
      
      # In production, this would use edge-tts or OpenAI TTS
      # For now, just print the text
      # system("edge-tts --text '#{text}' --write-media output.mp3")
      
      text
    end

    # Transcribe audio to text (speech-to-text)
    def transcribe(audio_file)
      # In production, this would use Whisper API or local whisper.cpp
      # For now, simulate transcription
      
      puts "🎙️  Transcribing #{audio_file}..."
      
      # Simulated transcription result
      {
        text: "refactor lib/engine.rb",
        confidence: 0.95,
        language: @language
      }
    end

    # Process a voice command
    def process_command(command, &block)
      puts "📝 Processing: #{command}"
      
      # Parse intent
      intent = VoiceNLU.parse(command)
      
      # Execute command
      result = execute_intent(intent)
      
      # Provide voice feedback
      feedback = generate_feedback(result)
      speak(feedback)
      
      # Call user callback if provided
      block.call(command, result) if block_given?
      
      result
    end

    private

    def execute_intent(intent)
      target = intent[:target]
      
      case intent[:action]
      when :refactor
        return { success: false, message: "File not found: #{target}" } unless File.exist?(target)
        
        code = File.read(target)
        engine = Engine.new
        result = engine.refactor(code)
        
        if result[:success]
          File.write(target, result[:code])
          { success: true, message: "Refactoring complete" }
        else
          { success: false, message: result[:error] || "Refactoring failed" }
        end
      when :analyze
        return { success: false, message: "File not found: #{target}" } unless File.exist?(target)
        
        code = File.read(target)
        engine = Engine.new
        result = engine.analyze(code)
        { success: true, message: "Analysis complete", data: result }
      when :suggest
        suggester = SmartSuggest.new
        suggestions = suggester.analyze_file(target) if File.exist?(target)
        suggestions ||= []
        { success: true, message: "Found #{suggestions.size} suggestions", data: suggestions }
      else
        { success: false, message: "Unknown command" }
      end
    rescue => e
      { success: false, message: "Error: #{e.message}" }
    end

    def generate_feedback(result)
      if result[:success]
        result[:message] || "Operation completed successfully"
      else
        result[:message] || "Operation failed"
      end
    end
  end

  # VoiceNLU - Natural Language Understanding for voice commands
  # Parses voice commands into structured intents
  class VoiceNLU
    def self.parse(command)
      new.parse(command)
    end

    def parse(command)
      command = command.downcase.strip
      
      # Refactor intent
      if command =~ /refactor\s+(.+)/
        return { action: :refactor, target: $1.strip }
      end
      
      # Analyze intent
      if command =~ /analyze\s+(.+)/
        return { action: :analyze, target: $1.strip }
      end
      
      # Show/list/suggest intent
      if command =~ /(show|list|suggest)\s+(code\s+)?smells?\s+in\s+(.+)/
        return { action: :suggest, target: $3.strip }
      end
      
      # Fix intent - map to refactor since fix_all is not implemented
      if command =~ /fix\s+(all|them|it)/
        return { action: :refactor, target: command }
      end
      
      # Default - treat as refactor target
      { action: :refactor, target: command }
    end
  end

  # WakeWordDetector - Detects wake word in audio stream
  class WakeWordDetector
    def initialize(wake_word = "hey master")
      @wake_word = wake_word
      @threshold = 0.8
    end

    def detect(audio_chunk)
      # In production, this would use a wake word detection library
      # like Porcupine or Snowboy
      
      # For now, simulate detection
      false
    end
  end
end
