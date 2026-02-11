# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  # TTS: Cloud-based TTS using Replicate's minimax/speech-02-turbo model
  # NOTE: This is one of three TTS implementations:
  #   - TTS (this file): Replicate cloud API - high quality, costs money
  #   - PiperTTS: Local neural TTS - fast, free, offline capable
  #   - EdgeTTS: Microsoft cloud - free, 400+ voices, no API key
  class TTS
    REPLICATE_TOKEN = ENV['REPLICATE_API_TOKEN']
    MODEL = 'minimax/speech-02-turbo'
    VOICE = 'Casual_Guy'
    MAX_PARALLEL = 3
    POLL_INTERVAL = 0.5
    MAX_POLLS = 60

    def initialize
      @queue = Queue.new
      @mutex = Mutex.new
      @playing = false
      @worker = nil
    end

    def speak(text)
      return unless REPLICATE_TOKEN
      return if text.nil? || text.strip.empty?

      chunks = split_into_chunks(text)
      chunks.each { |chunk| @queue.push(chunk) }
      start_worker unless @worker&.alive?
    end

    def speaking?
      @playing || !@queue.empty?
    end

    def stop
      @queue.clear
      @playing = false
    end

    private

    def start_worker
      @worker = Thread.new do
        while (chunk = @queue.pop(true) rescue nil) || !@queue.empty?
          break unless chunk
          audio_url = generate_audio(chunk)
          play_audio(audio_url) if audio_url
        end
      end
    end

    def split_into_chunks(text, max_chars: 200)
      # Split on sentence boundaries for natural TTS
      sentences = text.split(/(?<=[.!?])\s+/)
      chunks = []
      current = ""

      sentences.each do |sentence|
        if (current + " " + sentence).length > max_chars
          chunks << current.strip unless current.empty?
          current = sentence
        else
          current = current.empty? ? sentence : "#{current} #{sentence}"
        end
      end
      chunks << current.strip unless current.empty?
      chunks
    end

    def generate_audio(text)
      uri = URI("https://api.replicate.com/v1/models/#{MODEL}/predictions")
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{REPLICATE_TOKEN}"
      request['Content-Type'] = 'application/json'
      request['Prefer'] = 'wait'

      request.body = {
        input: {
          text: text,
          voice_id: VOICE,
          speed: 1.0
        }
      }.to_json

      response = http.request(request)
      data = JSON.parse(response.body)

      # If immediate result
      return data['output'] if data['output']

      # Otherwise poll for completion
      poll_for_result(data['urls']['get']) if data.dig('urls', 'get')
    rescue => e
      nil
    end

    def poll_for_result(url)
      uri = URI(url)
      MAX_POLLS.times do
        sleep POLL_INTERVAL

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{REPLICATE_TOKEN}"

        response = http.request(request)
        data = JSON.parse(response.body)

        case data['status']
        when 'succeeded'
          return data['output']
        when 'failed', 'canceled'
          return nil
        end
      end
      nil
    end

    def play_audio(url)
      return unless url
      @mutex.synchronize { @playing = true }

      begin
        # Download to temp file
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        
        response = http.get(uri.request_uri)
        return unless response.is_a?(Net::HTTPSuccess)

        temp = File.join(Dir.tmpdir, "master_tts_#{SecureRandom.hex(4)}.wav")
        File.binwrite(temp, response.body)

        # Play based on platform
        case RUBY_PLATFORM
        when /openbsd/
          system("aucat -i #{temp}")
        when /darwin/
          system("afplay #{temp}")
        when /linux/
          system("aplay -q #{temp} 2>/dev/null || paplay #{temp} 2>/dev/null")
        when /mingw|mswin/
          # Windows: use PowerShell
          system("powershell -c \"(New-Object Media.SoundPlayer '#{temp}').PlaySync()\"")
        end

        File.delete(temp) rescue nil
      ensure
        @mutex.synchronize { @playing = false }
      end
    end
  end

  # Parallel TTS generator - generates multiple chunks simultaneously
  class ParallelTTS < TTS
    def speak(text)
      return unless REPLICATE_TOKEN
      return if text.nil? || text.strip.empty?

      chunks = split_into_chunks(text)
      return if chunks.empty?

      # Generate all audio in parallel
      audio_urls = parallel_generate(chunks)

      # Play sequentially
      audio_urls.compact.each { |url| play_audio(url) }
    end

    private

    def parallel_generate(chunks)
      threads = chunks.first(MAX_PARALLEL).map.with_index do |chunk, i|
        Thread.new { [i, generate_audio(chunk)] }
      end

      results = threads.map(&:value).sort_by(&:first).map(&:last)

      # Generate remaining chunks if any
      if chunks.size > MAX_PARALLEL
        chunks[MAX_PARALLEL..].each do |chunk|
          results << generate_audio(chunk)
        end
      end

      results
    end
  end
end
