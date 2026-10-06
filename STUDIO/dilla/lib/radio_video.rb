# frozen_string_literal: true

require "fileutils"
require "socket"

module RadioVideo
  ROOT = File.expand_path("../../..", __dir__)
  DILLA_ROOT = File.expand_path("..", __dir__)
  RADIO_TUNNEL = File.join(ROOT, "RAILS", "brgen", "app", "javascript", "radio_brgen_tunnel.js")
  DEFAULT_AUDIO = File.join(DILLA_ROOT, "dilla.wav")
  DEFAULT_OUTPUT = File.join(DILLA_ROOT, "dilla.mp4")
  WIDTH = 720
  HEIGHT = 1280
  FPS = 30

  module_function

  def run(argv)
    input = File.expand_path(argv.shift || ENV.fetch("DILLA_VIDEO_AUDIO", DEFAULT_AUDIO))
    output = File.expand_path(argv.shift || ENV.fetch("DILLA_VIDEO_OUT", DEFAULT_OUTPUT))
    seconds = video_seconds

    abort "video: missing #{input} — run dilla showcase first" unless File.file?(input) && File.size?(input)
    abort "video: BRGEN radio tunnel is missing at #{RADIO_TUNNEL}" unless File.file?(RADIO_TUNNEL)

    browser = browser_path or abort "video: no Chrome/Chromium browser found"
    ffmpeg = executable("ffmpeg") or abort "video: ffmpeg is required"
    tmp = Dir.mktmpdir("dilla-video-")
    capture = File.join(tmp, "radio.webm")

    server = Server.new(
      audio: input,
      tunnel: RADIO_TUNNEL,
      html: page_html(seconds),
      output: capture
    )
    url = "http://127.0.0.1:#{server.port}/"

    warn "video0: BRGEN tunnel + #{File.basename(input)} -> #{output}"
    warn "video0: #{WIDTH}x#{HEIGHT} #{FPS}fps H.264/AAC, #{format_seconds(seconds)} cap"

    pid = Process.spawn(
      browser,
      "--headless=new",
      "--autoplay-policy=no-user-gesture-required",
      "--disable-dev-shm-usage",
      "--no-first-run",
      "--no-default-browser-check",
      "--window-size=#{WIDTH},#{HEIGHT}",
      url,
      out: File::NULL,
      err: File::NULL
    )

    begin
      abort "video: browser did not produce a capture" unless server.wait(timeout: [seconds + 45.0, 90.0].max)
      terminate(pid)
      transcode!(ffmpeg, capture, output, seconds)
    ensure
      terminate(pid)
      server.close
      FileUtils.remove_entry(tmp) if File.exist?(tmp)
    end

    size_mb = (File.size(output) / 1_048_576.0).round(1)
    warn "video0: wrote #{output} (#{size_mb} MB)"
    output
  end

  def video_seconds
    raw = ENV.fetch("DILLA_VIDEO_SECONDS", "90")
    value = Float(raw, exception: false)
    abort "video: DILLA_VIDEO_SECONDS must be 0 or a positive number" unless value && value >= 0
    value
  end

  def executable(name)
    candidates = [
      "/opt/homebrew/bin/#{name}",
      "/usr/local/bin/#{name}",
      *ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
    ]
    candidates.uniq.find { |path| File.executable?(path) && !File.directory?(path) }
  end

  def browser_path
    candidates = [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      "/opt/homebrew/bin/google-chrome",
      "/opt/homebrew/bin/chromium",
      "/usr/local/bin/google-chrome",
      "/usr/local/bin/chromium"
    ]
    candidates.find { |path| File.executable?(path) } || executable("google-chrome") || executable("chromium") || executable("chrome")
  end

  def terminate(pid)
    return unless pid
    Process.kill("TERM", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    begin
      Process.kill("KILL", pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end

  def transcode!(ffmpeg, capture, output, seconds)
    FileUtils.mkdir_p(File.dirname(output))
    args = [
      ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
      "-i", capture
    ]
    args += ["-t", seconds.to_s] if seconds.positive?
    args.concat([
      "-vf", "scale=#{WIDTH}:#{HEIGHT}:force_original_aspect_ratio=decrease,pad=#{WIDTH}:#{HEIGHT}:(ow-iw)/2:(oh-ih)/2:black,format=yuv420p",
      "-r", FPS.to_s,
      "-c:v", "libx264",
      "-preset", "medium",
      "-profile:v", "high",
      "-level:v", "3.1",
      "-crf", "24",
      "-c:a", "aac",
      "-b:a", "128k",
      "-ar", "48000",
      "-ac", "2",
      "-movflags", "+faststart",
      output
    ])
    system(*args) or abort "video: ffmpeg could not write #{output}"
  end

  def format_seconds(value)
    return "full source" if value.zero?
    format("%.1fs", value)
  end

  def page_html(seconds)
    <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=#{WIDTH},height=#{HEIGHT},initial-scale=1">
        <style>
          html, body { margin: 0; padding: 0; width: #{WIDTH}px; height: #{HEIGHT}px; background: #000; overflow: hidden; }
          canvas { display: block; width: #{WIDTH}px; height: #{HEIGHT}px; }
        </style>
        <script type="importmap">
        {
          "imports": {
            "pub4/visual_field": "/visual_field.js"
          }
        }
        </script>
      </head>
      <body>
        <canvas id="radio-canvas" aria-label="Radio Bergen visualizer"></canvas>
        <audio id="audio" preload="auto"></audio>
        <script type="module">
          import { VisualEngine } from "/radio_brgen_tunnel.js"

          const audio = document.getElementById("audio")
          const canvas = document.getElementById("radio-canvas")
          const limit = #{seconds}

          audio.src = "/audio.wav"
          const context = new (window.AudioContext || window.webkitAudioContext)()
          const source = context.createMediaElementSource(audio)
          const analyser = context.createAnalyser()
          analyser.fftSize = 2048
          analyser.smoothingTimeConstant = 0.58
          const destination = context.createMediaStreamDestination()
          source.connect(analyser)
          analyser.connect(destination)

          const bins = new Uint8Array(analyser.frequencyBinCount)
          const previous = new Uint8Array(analyser.frequencyBinCount)
          const visual = new VisualEngine(canvas)
          const videoStream = canvas.captureStream(#{FPS})
          const stream = new MediaStream([
            ...videoStream.getVideoTracks(),
            ...destination.stream.getAudioTracks()
          ])

          const mimeTypes = [
            "video/webm;codecs=vp9,opus",
            "video/webm;codecs=vp8,opus",
            "video/webm"
          ]
          const mimeType = mimeTypes.find((type) => MediaRecorder.isTypeSupported(type))
          if (!mimeType) {
            await fetch("/fail", { method: "POST", body: "MediaRecorder WebM unavailable" })
            throw new Error("MediaRecorder WebM unavailable")
          }

          const chunks = []
          const recorder = new MediaRecorder(stream, {
            mimeType,
            videoBitsPerSecond: 4_000_000,
            audioBitsPerSecond: 128_000
          })

          const bandData = () => {
            analyser.getByteFrequencyData(bins)
            const len = bins.length
            const bassEnd = Math.max(1, Math.floor(len * 0.012))
            const midEnd = Math.max(bassEnd + 1, Math.floor(len * 0.09))
            let bassSum = 0
            let midSum = 0
            let highSum = 0
            let fluxSum = 0
            for (let i = 0; i < len; i++) {
              const value = bins[i]
              fluxSum += Math.max(0, value - previous[i])
              previous[i] = value
              if (i < bassEnd) bassSum += value
              else if (i < midEnd) midSum += value
              else highSum += value
            }
            const bass = Math.min(1, bassSum / bassEnd / 255)
            const mid = Math.min(1, (midSum / (midEnd - bassEnd) / 255) * 0.8)
            const high = Math.min(1, (highSum / (len - midEnd) / 255) * 2.6 * 0.6)
            const average = (bass + mid + high) / 3
            const flux = Math.min(1, (fluxSum / len / 255) * 5)
            return { bass, mid, high, average, beat: flux, flux }
          }

          let raf
          const draw = () => {
            try {
              visual.update(bandData())
              visual.render()
            } catch (error) {
              console.warn("dilla-video visual frame", error)
            }
            raf = requestAnimationFrame(draw)
          }

          let finished = false
          const finish = () => {
            if (finished) return
            finished = true
            cancelAnimationFrame(raf)
            audio.pause()
            if (recorder.state !== "inactive") recorder.stop()
          }

          recorder.ondataavailable = (event) => {
            if (event.data.size) chunks.push(event.data)
          }

          recorder.onstop = async () => {
            const blob = new Blob(chunks, { type: mimeType })
            const response = await fetch("/capture", { method: "POST", body: blob })
            if (!response.ok) throw new Error(await response.text())
          }

          audio.addEventListener("ended", finish, { once: true })
          audio.addEventListener("loadedmetadata", async () => {
            await context.resume()
            audio.currentTime = 0
            recorder.start()
            draw()
            await audio.play()
            const duration = limit > 0 ? Math.min(limit, audio.duration) : audio.duration
            window.setTimeout(finish, Math.max(0.1, duration) * 1000)
          }, { once: true })
        </script>
      </body>
      </html>
    HTML
  end

  class Server
    attr_reader :port

    def initialize(audio:, tunnel:, html:, output:)
      @audio = audio
      @tunnel = tunnel
      @html = html
      @output = output
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @captured = false
      @error = nil
      @thread = Thread.new { accept_loop }
    end

    def wait(timeout:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      @mutex.synchronize do
        until @captured || @error
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0
          @condition.wait(@mutex, remaining)
        end
        raise @error if @error
        @captured
      end
    end

    def close
      @server.close
      @thread&.kill
      @thread&.join
    rescue IOError, Errno::EBADF
      nil
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        Thread.new(socket) do |client|
          handle(client)
        rescue StandardError => e
          @mutex.synchronize do
            @error ||= e
            @condition.broadcast
          end
        ensure
          client.close rescue nil
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def handle(client)
      request = client.gets
      return unless request

      method, target, = request.split
      headers = {}
      while (line = client.gets)
        line = line.chomp
        break if line.empty? || line == "\r"
        key, value = line.split(":", 2)
        headers[key.downcase] = value.to_s.strip if key
      end

      path = target.to_s.split("?", 2).first
      case [method, path]
      when ["GET", "/"]
        respond(client, 200, "text/html; charset=utf-8", @html)
      when ["GET", "/radio_brgen_tunnel.js"]
        respond_file(client, @tunnel, "text/javascript; charset=utf-8")
      when ["GET", "/visual_field.js"]
        respond(client, 200, "text/javascript; charset=utf-8", "export function publishVisual() {}")
      when ["GET", "/audio.wav"]
        respond_file(client, @audio, "audio/wav")
      when ["POST", "/capture"]
        receive_body(client, headers.fetch("content-length").to_i, @output)
        respond(client, 200, "text/plain; charset=utf-8", "ok")
        @mutex.synchronize do
          @captured = true
          @condition.broadcast
        end
      when ["POST", "/fail"]
        length = headers.fetch("content-length", "0").to_i
        message = read_body(client, length)
        @mutex.synchronize do
          @error = RuntimeError.new("browser export failed: #{message}")
          @condition.broadcast
        end
        respond(client, 500, "text/plain; charset=utf-8", "failed")
      else
        respond(client, 404, "text/plain; charset=utf-8", "not found")
      end
    end

    def respond_file(client, path, type)
      size = File.size(path)
      client.write("HTTP/1.1 200 OK\r\nContent-Type: #{type}\r\nContent-Length: #{size}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
      File.open(path, "rb") do |file|
        while (chunk = file.read(65_536))
          client.write(chunk)
        end
      end
    end

    def respond(client, status, type, body)
      body = body.to_s.b
      client.write("HTTP/1.1 #{status} OK\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n")
      client.write(body)
    end

    def receive_body(client, length, path)
      raise "video: browser sent an empty capture" if length <= 0
      File.open(path, "wb") do |file|
        remaining = length
        while remaining.positive?
          chunk = client.read([remaining, 65_536].min)
          raise EOFError, "capture ended early" unless chunk
          file.write(chunk)
          remaining -= chunk.bytesize
        end
      end
    end

    def read_body(client, length)
      return "" if length <= 0
      client.read(length).to_s
    end
  end
end
