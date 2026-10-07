# frozen_string_literal: true

require "json"
require "net/http"
require "rexml/document"
require "uri"
require "cgi"

module Master
  module Io
    class YoutubeTranscript
      TIER = :guarded
      NAME = "youtube_transcript".freeze
      DESCRIPTION = "Fetch available public YouTube captions as untrusted transcript text; no audio execution.".freeze
      TIMEOUT = 15
      MAX_BYTES = 2 * 1024 * 1024
      VIDEO_RE = %r{(?:v=|youtu\.be/|youtube\.com/shorts/|youtube\.com/embed/)([A-Za-z0-9_-]{11})}.freeze
      CLIENTS = %w[ANDROID WEB TVHTML5_SIMPLY_EMBEDDED_PLAYER].freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(url:, language: nil, timestamps: false)
        video_id = video_id_for(url)
        return Result.err("youtube_transcript: invalid YouTube URL or video id", category: :validation) unless video_id

        perm = @governor.permit?(NAME, TIER, video_id)
        return perm if perm.err?

        track = caption_track(video_id, language:)
        return Result.err("youtube_transcript: no public caption track found", category: :infrastructure) unless track

        transcript = download(track.fetch("baseUrl"), timestamps:)
        value = injection_guard.screen(transcript, tool: NAME, source: "https://www.youtube.com/watch?v=#{video_id}", bus: @bus)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: "youtube")
        @bus&.publish("tool:after", tool: NAME, video_id:)
        Result.ok(value)
      rescue StandardError => e
        Result.err("youtube_transcript: #{e.message}", category: :infrastructure)
      end

      private

      def video_id_for(value)
        text = value.to_s
        return text if text.match?(/\A[A-Za-z0-9_-]{11}\z/)

        VIDEO_RE.match(text)&.captures&.first
      end

      def caption_track(video_id, language:)
        CLIENTS.each do |client|
          player = player_response(video_id, client)
          tracks = Array(player.dig("captions", "playerCaptionsTracklistRenderer", "captionTracks"))
          preferred = tracks.find { |t| language.to_s.empty? || t["languageCode"].to_s == language.to_s }
          return preferred || tracks.first unless tracks.empty?
        rescue StandardError => e
          @bus&.publish("tool:warning", tool: NAME, message: "#{client}: #{e.message}")
        end
        nil
      end

      def player_response(video_id, client)
        watch = get("https://www.youtube.com/watch?v=#{video_id}")
        api_key = watch[/INNERTUBE_API_KEY\s*["']\s*:\s*["']([^"']+)/, 1]
        raise "player API key not found" if api_key.to_s.empty?

        uri = URI("https://www.youtube.com/youtubei/v1/player?key=#{CGI.escape(api_key)}")
        address = SsrfGuard.pinned_address(uri)
        raise "refused internal/reserved address" unless address

        response = http_json(uri, address, {
          context: {
            client: {
              clientName: client,
              clientVersion: client_version(client)
            }
          },
          videoId: video_id
        })
        raise "player API HTTP #{response.code}" unless response.code == "200"

        JSON.parse(response.body.to_s)
      end

      def client_version(client)
        {
          "ANDROID" => "20.10.38",
          "WEB" => "2.20261007.01.00",
          "TVHTML5_SIMPLY_EMBEDDED_PLAYER" => "7.20261006.18.00"
        }.fetch(client)
      end

      def download(base_url, timestamps:)
        response = get_response(base_url)
        return "Error: caption HTTP #{response.code}" unless response.code == "200"

        document = REXML::Document.new(response.body.to_s)
        lines = REXML::XPath.match(document, "//text").filter_map do |node|
          text = CGI.unescapeHTML(node.text.to_s).gsub(/\s+/, " ").strip
          next if text.empty?

          timestamps ? "[#{format_time(node.attributes["start"].to_f)}] #{text}" : text
        end
        lines.join(timestamps ? "\n" : " ").byteslice(0, MAX_BYTES)
      end

      def format_time(seconds)
        total = seconds.to_f.round
        format("%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
      end

      def get(url)
        response = get_response(url)
        raise "HTTP #{response.code}" unless response.code == "200"

        response.body.to_s.byteslice(0, MAX_BYTES)
      end

      def get_response(url)
        uri = URI(url)
        address = SsrfGuard.pinned_address(uri)
        raise "refused internal/reserved address" unless address

        client = SsrfGuard.http_for(uri, address)
        client.read_timeout = TIMEOUT
        client.open_timeout = TIMEOUT
        client.start do |http|
          if uri.host == "www.youtube.com" && uri.path == "/watch"
            http.get(uri.request_uri, "User-Agent" => "MASTER/1 (youtube_transcript)")
          else
            http.get(uri.request_uri, "User-Agent" => "MASTER/1 (youtube_transcript)")
          end
        end
      end

      def http_json(uri, address, payload)
        client = SsrfGuard.http_for(uri, address)
        client.read_timeout = TIMEOUT
        client.open_timeout = TIMEOUT
        client.start do |http|
          request = Net::HTTP::Post.new(uri.request_uri)
          request["User-Agent"] = "MASTER/1 (youtube_transcript)"
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(payload)
          http.request(request)
        end
      end

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end
    end
  end
end
