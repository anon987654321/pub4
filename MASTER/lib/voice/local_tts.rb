# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "securerandom"
require "tmpdir"
require "uri"

module Master
  module Voice
    # A local expressive neural voice from the mlx-audio tool, installed as an
    # isolated user tool (`uv tool install mlx-audio`). Nothing here imports
    # Python: the tool is an executable, driven by argv or by its HTTP server.
    #
    # Which models speak which language, and with what voice, is data: the
    # `local_engines` list in the active voice.yml profile. An entry whose
    # language does not match, or whose binary is absent, is skipped, and the
    # caller falls through to Edge. Nothing in this file raises into a caller.
    module LocalTts
      BIN_NAME = "mlx_audio.tts.generate"
      SERVER_NAME = "mlx_audio.server"
      CLI_TIMEOUT_S = 240
      # A clause that the resident server has not answered in this long goes to
      # the next engine; a busy server must not hold up the speech.
      SERVER_TIMEOUT_S = 15

      module_function

      def entries
        Array(Policy.data["local_engines"]).select { |entry| entry.is_a?(Hash) }
      end

      def entries_for(language)
        entries.select { |entry| Array(entry["languages"]).map(&:to_s).include?(language.to_s) }
      end

      def bin(entry = {})
        candidates = [entry["bin"], ENV["MASTER_LOCAL_TTS_BIN"], File.join(Dir.home, ".local", "bin", BIN_NAME)]
        candidates.compact.map { |path| File.expand_path(path.to_s) }.find { |path| File.executable?(path) } ||
          ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, BIN_NAME) }.find { |path| File.executable?(path) }
      end

      def available?(entry) = !bin(entry).nil?

      # Writes a 24 kHz mono wav at out_path. False on any failure.
      #
      # An entry with a `server` url goes to a resident mlx_audio.server, which
      # keeps the model loaded: a one-shot command line pays the whole import and
      # model load again for every clause (measured 29 s against 1 s warm). When
      # the server is not up it is started in the background and this call
      # returns false, so the clause is spoken by the next engine in the chain
      # and the following ones find the model warm.
      def synthesize(entry, text, out_path)
        return false unless available?(entry)
        return via_server(entry, text, out_path) if entry["server"]

        via_cli(entry, text, out_path)
      end

      def server_uri(entry) = URI(entry.fetch("server"))

      def server_up?(entry)
        uri = server_uri(entry)
        Net::HTTP.start(uri.host, uri.port, open_timeout: 0.5, read_timeout: 1) { |http| http.get("/v1/models").code == "200" }
      rescue StandardError
        false
      end

      def server_bin(entry)
        sibling = File.join(File.dirname(bin(entry).to_s), SERVER_NAME)
        File.executable?(sibling) ? sibling : nil
      end

      # Detached, logging to .master/local_tts.log; at most once per process.
      def start_server(entry)
        return false if @started || !(command = server_bin(entry))

        uri = server_uri(entry)
        log = File.join(Master::ROOT, ".master", "local_tts.log")
        FileUtils.mkdir_p(File.dirname(log))
        pid = Process.spawn(command, "--host", uri.host, "--port", uri.port.to_s,
                            in: File::NULL, out: [log, "a"], err: [log, "a"], pgroup: true)
        Process.detach(pid)
        @started = true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LocalTts.start_server")
        false
      end

      def via_server(entry, text, out_path)
        start_server(entry) unless server_up?(entry)
        return false unless server_up?(entry)

        uri = server_uri(entry)
        request = Net::HTTP::Post.new("/v1/audio/speech", "Content-Type" => "application/json")
        request.body = JSON.generate(server_body(entry, text))
        response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: entry.fetch("timeout_s", SERVER_TIMEOUT_S)) { |http| http.request(request) }
        return false unless response.code == "200" && response.body.to_s.bytesize > 1000

        File.binwrite(out_path, response.body)
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LocalTts.via_server")
        false
      end

      def server_body(entry, text)
        body = { model: entry.fetch("model"), input: text, response_format: "wav" }
        body[:voice] = entry["voice"] unless entry["voice"].to_s.empty?
        body[:lang_code] = entry["lang_code"] unless entry["lang_code"].to_s.empty?
        body[:speed] = entry["speed"] if entry["speed"]
        body
      end

      def argv(entry, text, dir, prefix)
        args = [bin(entry), "--model", entry.fetch("model"), "--text", text, "--output_path", dir,
                "--file_prefix", prefix, "--audio_format", "wav"]
        args += ["--voice", entry["voice"].to_s] unless entry["voice"].to_s.empty?
        args += ["--lang_code", entry["lang_code"].to_s] unless entry["lang_code"].to_s.empty?
        args += ["--speed", entry["speed"].to_s] if entry["speed"]
        args
      end

      def via_cli(entry, text, out_path)
        Dir.mktmpdir("local_tts") do |dir|
          prefix = "t#{SecureRandom.hex(4)}"
          _out, _err, status = Master::Io::Exec.capture3(*argv(entry, text, dir, prefix), timeout: CLI_TIMEOUT_S)
          produced = Dir.glob(File.join(dir, "#{prefix}*.wav")).select { |p| File.size?(p) }.sort
          return false unless status.success? && !produced.empty?

          # Long input comes back as numbered segments; they join in order.
          return join(produced, out_path) if produced.size > 1

          FileUtils.cp(produced.first, out_path)
          File.size?(out_path) ? true : false
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "LocalTts.via_cli")
        false
      end

      def join(parts, out_path)
        inputs = parts.flat_map { |path| ["-i", path] }
        graph = "#{parts.each_index.map { |i| "[#{i}:a]" }.join}concat=n=#{parts.size}:v=0:a=1[out]"
        _out, _err, status = Master::Io::Exec.capture3("ffmpeg", "-y", *inputs, "-filter_complex", graph, "-map", "[out]", out_path)
        status.success? && File.size?(out_path) ? true : false
      end
    end
  end
end
