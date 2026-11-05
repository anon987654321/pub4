# frozen_string_literal: true

require "digest"
require "json"
require "uri"
require "shared/subprocess"
require "yaml"

module Brgen
  class WhypRadioImporter
    DEFAULT_AUDIO_ROOT = Rails.root.join("public/audio/whyp")
    DEFAULT_MANIFEST_ROOT = Rails.root.join("config/radio_whyp")
    DEFAULT_TIMEOUT = 1_800
    # Older yt-dlp builds stop at "Unable to extract __NUXT__" on whyp.it's
    # current pages; 2026.08.19 reads them (checked 2026-10-31).
    MIN_YTDLP = "2026.08.19"

    Result = Data.define(:manifest_path, :track_count, :audio_root, :missing)

    # A collection URL, or a list of track share URLs (with their tokens) named
    # by +name+. +credits+ ({ whyp id => { title:, artist: } }) overrides what
    # yt-dlp reads, which credits every upload to the uploader's account name.
    def initialize(collection_url: nil, track_urls: nil, name: nil, credits: {},
                   audio_root: DEFAULT_AUDIO_ROOT, manifest_root: DEFAULT_MANIFEST_ROOT)
      @track_urls = Array(track_urls).map { |url| validate_url(url) }
      @collection_url = validate_url(collection_url) if @track_urls.empty?
      @collection_slug = @track_urls.empty? ? slug_for(@collection_url) : name.to_s.presence || "whyp-tracks"
      @credits = credits.transform_keys(&:to_s)
      @audio_root = Pathname.new(audio_root).join(@collection_slug)
      @manifest_root = Pathname.new(manifest_root)
    end

    def call
      require_commands!
      @audio_root.mkpath
      @manifest_root.mkpath
      download_collection

      manifest = build_manifest
      manifest_path = @manifest_root.join("#{@collection_slug}.yml")
      write_manifest(manifest, manifest_path)

      missing = @track_urls.filter_map { |url| track_id(url) unless audio_file_for(track_id(url)) }
      Result.new(manifest_path, manifest.fetch("tracks").size, @audio_root, missing)
    end

    private

    attr_reader :collection_url, :collection_slug, :audio_root, :manifest_root, :track_urls, :credits

    def track_id(url) = URI.parse(url).path[%r{/tracks/(\d+)}, 1].to_s

    def validate_url(value)
      uri = URI.parse(value.to_s)
      abort "radio: collection must be a Whyp URL" unless %w[whyp.it www.whyp.it].include?(uri.host.to_s.downcase)

      value.to_s
    rescue URI::InvalidURIError
      abort "radio: invalid collection URL"
    end

    # Not collection_slug(url): a method of that name replaced the attr_reader
    # above, so build_manifest's collection_slug raised and no import ever wrote
    # a manifest.
    def slug_for(url)
      value = URI.parse(url).path.split("/").reject(&:blank?).last.to_s
      value = "collection-#{Digest::SHA256.hexdigest(url)[0, 12]}" if value.blank?
      value.gsub(/[^0-9A-Za-z_-]+/, "-").sub(/\A-+|-+\z/, "")[0, 80]
    end

    def require_commands!
      %w[yt-dlp ffmpeg].each do |command|
        available = Shared::Subprocess.on_path?(command)
        abort "radio: #{command} is required" unless available
      end
      require_ytdlp_version!
    end

    def require_ytdlp_version!
      stdout, = Shared::Subprocess.capture3("yt-dlp", "--version", timeout: 30)
      version = stdout.to_s.strip
      return if Gem::Version.new(version.tr("-", ".")) >= Gem::Version.new(MIN_YTDLP)

      abort "radio: yt-dlp #{version} cannot read whyp.it; need #{MIN_YTDLP} or later " \
            "(pip install --user -U yt-dlp, or the standalone build from its GitHub releases)"
    rescue ArgumentError
      abort "radio: could not read the yt-dlp version (#{version.inspect})"
    end

    def download_collection
      stdout, stderr, status = run_bounded(download_args)
      # A track list is one download per track: one deleted upload (whyp.it
      # answers 404) must not discard the rest, so it is reported, not fatal.
      return if status.success? || (track_urls.any? && Dir.glob(audio_root.join("*.mp3").to_s).any?)

      detail = [ stderr, stdout ].compact_blank.join("\n").lines.last(20).join
      abort "radio: yt-dlp failed\n#{detail}"
    rescue Shared::Subprocess::TimeoutError
      abort "radio: yt-dlp exceeded #{timeout_seconds}s"
    end

    def download_args
      [
        "yt-dlp",
        *(track_urls.empty? ? [ "--yes-playlist" ] : [ "--no-playlist", "--ignore-errors" ]),
        "--no-warnings", "--no-overwrites", "--write-info-json", "--write-thumbnail",
        "--extract-audio", "--audio-format", "mp3", "--audio-quality", "128K",
        "--output", audio_root.join("%(id)s.%(ext)s").to_s,
        *(track_urls.presence || [ collection_url ])
      ]
    end

    def run_bounded(argv)
      Shared::Subprocess.capture3(*argv, timeout: timeout_seconds)
    end

    def build_manifest
      infos = Dir.glob(audio_root.join("*.info.json").to_s).filter_map do |path|
        JSON.parse(File.read(path, encoding: "UTF-8"))
      rescue JSON::ParserError => error
        abort "radio: invalid yt-dlp metadata #{path}: #{error.message}"
      end

      tracks = infos.filter_map { |info| manifest_track(info) }.uniq { |row| row["source_url"] }
      abort "radio: yt-dlp produced no usable tracks" if tracks.empty?

      { "meta" => manifest_meta, "tracks" => tracks }
    end

    def manifest_meta
      {
        "source" => "Whyp",
        "collection_url" => collection_url,
        "track_urls" => track_urls.presence,
        "collection_id" => collection_slug,
        "audio_format" => "mp3",
        "audio_quality" => "128k",
        "privacy" => "public",
        "purpose" => "Radio seed media",
        "generated_at" => Time.current.iso8601,
        "rights_note" => "Imported from the operator-provided Whyp collection; verify publication rights before production redistribution."
      }.compact
    end

    def manifest_track(info)
      id = info["id"].to_s.presence
      title = credits.dig(id.to_s, :title).presence || info["title"].to_s.presence
      source_url = info["webpage_url"].presence || info["original_url"].presence
      return unless id && title && source_url

      audio_path = audio_file_for(id)
      return unless audio_path

      artwork_path = artwork_file_for(id)

      {
        "id" => id,
        "title" => title,
        "artist" => artist_for(id, info),
        "duration_seconds" => info["duration"]&.to_f&.round,
        "source_type" => "whyp",
        "source_url" => source_url,
        "audio" => relative_public_path(audio_path),
        "artwork" => artwork_path ? relative_public_path(artwork_path) : nil
      }.compact
    end

    # tracks.yml's credit first: yt-dlp names the uploader's account on every track.
    def artist_for(id, info)
      credits.dig(id.to_s, :artist).presence ||
        %w[artist creator uploader].lazy.filter_map { |key| info[key].presence }.first || "Brgen Radio"
    end

    def audio_file_for(id)
      candidate = audio_root.join("#{id}.mp3")
      candidate.file? && candidate.size.positive? ? candidate : nil
    end

    def artwork_file_for(id)
      %w[jpg jpeg png webp].map { |ext| audio_root.join("#{id}.#{ext}") }.find(&:file?)
    end

    def relative_public_path(path)
      path.relative_path_from(Rails.root).to_s
    end

    def write_manifest(manifest, path)
      File.write(
        path,
        "# GENERATED by COLLECTION=... bin/rails radio:import_whyp.\n" \
        "# Source media is operator-supplied; do not edit track rows by hand.\n" +
        YAML.dump(manifest).sub(/\A---\n/, "")
      )
    end

    def timeout_seconds
      seconds = Float(ENV.fetch("YTDLP_TIMEOUT", DEFAULT_TIMEOUT))
      seconds.positive? ? seconds : DEFAULT_TIMEOUT
    rescue ArgumentError
      DEFAULT_TIMEOUT
    end
  end
end
