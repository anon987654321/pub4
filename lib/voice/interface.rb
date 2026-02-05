# frozen_string_literal: true
require "json"
require "net/http"

module Master
  module Voice
    class Interface
      WHISPER_MODEL = "whisper-1"
      
      def initialize(llm: nil)
        @llm = llm || Master::LLM.new
        @api_key = ENV["OPENAI_API_KEY"] || ENV["OPENROUTER_API_KEY"]
      end
      
      # Start interactive voice session
      def start_session
        puts "Voice interface starting..."
        puts "Note: Audio recording requires 'ruby-audio' or 'portaudio' gem"
        puts "Press Ctrl+C to exit"
        
        loop do
          puts "\nPress Enter to record (or type 'quit' to exit)..."
          input = gets&.strip
          break if input == "quit"
          
          # Simulate recording (would use actual audio in production)
          puts "Recording... (simulated)"
          sleep(1)
          
          # In production, this would record audio
          # audio_file = record_audio
          # transcript = transcribe_audio(audio_file)
          
          # For now, accept text input
          puts "Transcript (or type command): "
          transcript = gets&.strip
          break if transcript.nil? || transcript.empty?
          
          # Parse intent and execute
          command = parse_intent(transcript)
          puts "Executing: #{command}"
          
          result = execute_command(command)
          
          # Generate and play audio response
          if result.ok?
            response_text = format_response(result.value)
            puts "\nResponse: #{response_text}"
            
            # In production: synthesize_speech(response_text)
          else
            puts "\nError: #{result.error}"
          end
        end
      end
      
      # Transcribe audio file using Whisper API
      def transcribe_audio(audio_file)
        return Result.err("No API key found") unless @api_key
        return Result.err("Audio file not found") unless File.exist?(audio_file)
        
        # OpenAI Whisper API call
        uri = URI("https://api.openai.com/v1/audio/transcriptions")
        
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        
        form_data = [
          ["file", File.open(audio_file)],
          ["model", WHISPER_MODEL]
        ]
        request.set_form(form_data, "multipart/form-data")
        
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end
        
        if response.code == "200"
          data = JSON.parse(response.body)
          Result.ok(text: data["text"])
        else
          Result.err("Transcription failed: #{response.body}")
        end
      rescue => e
        Result.err("Transcription error: #{e.message}")
      end
      
      # Parse natural language into CLI command
      def parse_intent(transcript)
        # Simple pattern matching for common commands
        case transcript.downcase
        when /analyze.*authentication|auth/i
          "analyze lib/auth.rb"
        when /analyze.*security/i
          "analyze . --focus security"
        when /fix\s+(.+)/i
          "fix #{$1}"
        when /show.*principles/i
          "principles"
        when /cost|spending/i
          "cost"
        else
          # Use LLM to parse complex intents
          prompt = <<~PROMPT
            Convert this voice command to a MASTER CLI command:
            "#{transcript}"
            
            Available commands: analyze, fix, principles, cost, smells, evolve
            Return only the command, no explanation.
          PROMPT
          
          result = @llm.ask(prompt, tier: :fast)
          result.ok? ? result.value.strip : transcript
        end
      end
      
      # Execute CLI command
      def execute_command(command)
        # Parse command
        parts = command.split
        cmd = parts.first
        args = parts[1..]
        
        # Execute via CLI handler
        cli = Master::CLI.new
        
        case cmd&.downcase
        when "analyze", "az"
          cli.send(:analyze_files, args)
        when "fix"
          cli.send(:fix_file, args.first)
        when "principles", "p"
          cli.send(:show_principles)
          Result.ok(message: "Principles displayed")
        when "cost"
          Result.ok(message: cli.send(:instance_variable_get, :@llm).cost_summary)
        else
          Result.err("Unknown command: #{cmd}")
        end
      rescue => e
        Result.err("Execution error: #{e.message}")
      end
      
      # Synthesize speech from text (stub)
      def synthesize_speech(text)
        # In production, would use TTS API
        # For now, just return success
        Result.ok(message: "TTS not implemented")
      end
      
      # Play audio file (stub)
      def play_audio(audio_file)
        # In production, would use audio playback
        Result.ok(message: "Audio playback not implemented")
      end
      
      private
      
      def format_response(result)
        case result
        when Hash
          result[:message] || result.inspect
        when String
          result
        else
          result.inspect
        end
      end
      
      # Record audio from microphone (stub)
      def record_audio(duration: 5)
        # In production, would use ruby-audio or portaudio
        # For now, return a dummy path
        "/tmp/recording.wav"
      end
    end
  end
end
