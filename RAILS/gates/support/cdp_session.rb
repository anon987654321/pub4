# frozen_string_literal: true

require "json"
require "socket"
require "base64"
require "digest/sha1"
require "securerandom"
require "tmpdir"
require "fileutils"
require "net/http"

module Deploy
  # Minimal Chrome DevTools Protocol client — stdlib only.
  #
  # The gates run under bare `ruby` from gates/runner.rb, but ferrum and
  # selenium only exist inside the per-app bundles. Rather than make every
  # browser-backed gate bundle-dependent (and therefore skipped in practice,
  # the way design_metrics_gate's DESIGN_METRICS_BROWSER probe is), this speaks
  # CDP directly over a WebSocket we implement here. ~200 lines buys us zero
  # gem dependencies, real Input events for the keyboard gate, and Chrome flags
  # ferrum does not expose (host-resolver-rules for brgen's vertical subdomains).
  #
  #   CdpSession.open(host_map: { "markedsplass.brgen.no" => "127.0.0.1:38182" }) do |cdp|
  #     cdp.viewport(390, 844)
  #     cdp.navigate("http://markedsplass.brgen.no/")
  #     cdp.evaluate("document.title")
  #   end
  class CdpSession
    class Error < StandardError; end
    class Timeout < Error; end
    class Unavailable < Error; end
    class JsError < Error; end
    # The socket is mid-frame and can no longer be trusted. Distinct from
    # Timeout because a timeout is retryable and this is not.
    class Desync < Error; end

    # No legitimate CDP message is anywhere near this large. Without the cap, a
    # desynchronised read parses arbitrary payload bytes as a 64-bit length and
    # read_nonblock tries to allocate it — which surfaces as a NoMemoryError
    # that kills the whole runner instead of one surface.
    MAX_FRAME_BYTES = 64 * 1024 * 1024

    CHROME_PATHS = [
      ENV["CHROME_PATH"],
      "/usr/local/bin/chromium",
      "/usr/local/bin/chrome",
      "/usr/local/chrome/chrome",
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/usr/bin/chromium",
      "/usr/bin/google-chrome",
    ].compact.freeze

    DEFAULT_TIMEOUT = Integer(ENV.fetch("GATE_BROWSER_TIMEOUT", "20"))

    def self.chrome_path
      CHROME_PATHS.find { |path| File.executable?(path) }
    end

    def self.available?
      !chrome_path.nil?
    end

    # host_map: { "markedsplass.brgen.no" => "127.0.0.1:38182", ... }
    # Rules are applied in order and first match wins, so callers should pass
    # specific hosts before any wildcard.
    def self.open(host_map: {}, timeout: DEFAULT_TIMEOUT, webgl: false)
      session = new(host_map: host_map, timeout: timeout, webgl: webgl)
      session.start
      yield session
    ensure
      session&.close
    end

    attr_reader :events

    # webgl: opt into SwiftShader for a surface that is made of WebGL. Off by
    # default because software GL is slow and rasterises text differently, which
    # the layout and CSS gates would feel.
    def initialize(host_map: {}, timeout: DEFAULT_TIMEOUT, webgl: false)
      @host_map = host_map
      @timeout = timeout
      @webgl = webgl
      @id = 0
      @events = []
      @pending = {}
      @recoveries = 0
      @boot_scripts = []
    end

    # How many times a desynchronised socket may be rebuilt before we conclude
    # the browser itself is unhealthy. Without a cap a wedged Chrome would be
    # reconnected once per command for the rest of the run. A width sweep makes
    # ~130 navigations and recovers a handful of times, so the cap is set well
    # above normal noise and only trips on a browser that is genuinely sick.
    MAX_RECOVERIES = 25

    def start
      chrome = self.class.chrome_path
      raise Unavailable, "no Chrome/Chromium executable (set CHROME_PATH)" unless chrome

      @profile = Dir.mktmpdir("pub4-gate-cdp")
      @pid = spawn_chrome(chrome)
      ws_url = discover_page_target
      connect(ws_url)
      enable_domains
      self
    end

    def close
      @socket&.close
    rescue StandardError # scan: intentional — teardown; the session is ending either way
      nil
    ensure
      reap_chrome
      # Chrome keeps writing to the profile until it has fully exited, so a
      # remove_entry racing that write blows up mid-traverse. Reaping first
      # makes it rare; swallowing makes a leftover tmpdir a non-event.
      begin
        FileUtils.remove_entry(@profile) if @profile && File.directory?(@profile)
      rescue StandardError # scan: intentional — teardown; the socket is closing either way
        nil
      end
    end

    def reap_chrome
      return unless @pid

      Process.kill("TERM", @pid)
      deadline = monotonic + 5
      loop do
        break if Process.waitpid(@pid, Process::WNOHANG)
        break if monotonic > deadline

        sleep 0.05
      end
      Process.kill("KILL", @pid) if monotonic > deadline
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    ensure
      @pid = nil
    end

    # --- high level ---------------------------------------------------------

    def viewport(width, height, mobile: false, scale: 1)
      send_cmd("Emulation.setDeviceMetricsOverride",
               width: width, height: height, deviceScaleFactor: scale, mobile: mobile)
    end

    def headers(hash)
      send_cmd("Network.setExtraHTTPHeaders", headers: hash)
    end

    def clear_cookies
      send_cmd("Network.clearBrowserCookies")
    end

    # Navigate and wait for readyState complete. Returns the HTTP-ish status we
    # can recover from the Navigation timing entry (Chrome exposes responseStatus
    # on PerformanceNavigationTiming).
    def navigate(url, settle: 0.2)
      send_cmd("Page.navigate", url: url)
      deadline = monotonic + @timeout
      loop do
        state = begin
          evaluate("document.readyState")
        rescue JsError, Timeout
          nil
        end
        break if state == "complete"
        raise Timeout, "navigate timeout: #{url}" if monotonic > deadline

        sleep 0.05
      end
      await_webfonts
      sleep settle if settle.positive?
      url
    end

    # readyState "complete" does not mean the webfonts have applied, and text
    # laid out in the fallback face measures differently from the real one, so
    # waiting here makes a layout reading independent of font-cache state.
    #
    # Honest note on why this was added: it was written to explain the
    # .nearby-chat-widget-tab snapshot flapping between 92px and 102px, and that
    # diagnosis was WRONG — the widths are identical in both faces. The real
    # cause is that the tab's LABEL changes after load: the server renders
    # "chat" (92px) and nearby_chat_controller#syncLabelsFromFrame rewrites it
    # to the room name, "brgen" (102px), once the frame arrives. The snapshot
    # records whichever side of that race it caught, which is why re-baselining
    # never converged. See FINAL_TODO P0.9.
    #
    # This wait is kept because measuring layout before fonts settle is wrong on
    # its own terms, not because it fixed that. It does not fix that.
    #
    # Bounded and non-fatal: a page with no webfonts resolves immediately, and a
    # font that never loads costs FONT_WAIT rather than the run.
    FONT_WAIT = 3.0

    # document.fonts.ready, not document.fonts.status. `status` reads "loaded"
    # whenever no load is *currently pending* — including before a lazily
    # triggered load has started — so polling it returned immediately and
    # changed nothing. The promise is the actual settle signal.
    def await_webfonts
      evaluate(<<~JS, await_promise: true)
        (async () => {
          if (!document.fonts) return "none";
          await Promise.race([
            document.fonts.ready,
            new Promise((r) => setTimeout(r, #{(FONT_WAIT * 1000).to_i}))
          ]);
          return document.fonts.status;
        })()
      JS
    rescue JsError, Timeout
      nil
    end

    def status
      evaluate("performance.getEntriesByType('navigation')[0]?.responseStatus ?? null")
    end

    # Runtime.evaluate with returnByValue. Raises JsError on an uncaught throw
    # so a broken probe is loud rather than silently nil.
    def evaluate(js, await_promise: false)
      res = send_cmd("Runtime.evaluate",
                     expression: js,
                     returnByValue: true,
                     awaitPromise: await_promise,
                     userGesture: true)
      if (details = res["exceptionDetails"])
        text = details.dig("exception", "description") || details["text"]
        raise JsError, text.to_s.lines.first.to_s.strip
      end
      res.dig("result", "value")
    end

    # Script that runs before any page script on every subsequent navigation.
    # Remembered so a rebuilt connection re-installs it — otherwise a recovery
    # would silently drop the determinism harness and later surfaces would be
    # measured under different conditions than earlier ones.
    def on_new_document(js)
      @boot_scripts << js
      send_cmd("Page.addScriptToEvaluateOnNewDocument", source: js)
    end

    KEY_CODES = {
      "Tab" => [9, "Tab"], "Enter" => [13, "Enter"], "Escape" => [27, "Escape"],
      "Space" => [32, "Space"], "ArrowDown" => [40, "ArrowDown"], "ArrowUp" => [38, "ArrowUp"],
    }.freeze

    def press(key, shift: false)
      code, dom_key = KEY_CODES.fetch(key)
      modifiers = shift ? 8 : 0
      %w[rawKeyDown keyUp].each do |type|
        send_cmd("Input.dispatchKeyEvent",
                 type: type, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code,
                 key: dom_key, code: dom_key, modifiers: modifiers)
      end
    end

    def screenshot(path)
      res = send_cmd("Page.captureScreenshot", format: "png", captureBeyondViewport: false)
      File.binwrite(path, Base64.decode64(res.fetch("data")))
      path
    end

    def console_errors
      @events
        .select { |e| e["method"] == "Log.entryAdded" }
        .map { |e| e.dig("params", "entry") }
        .select { |entry| entry && entry["level"] == "error" }
        .map { |entry| entry["text"].to_s }
    end

    # --- transport ----------------------------------------------------------

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def spawn_chrome(chrome)
      args = [
        chrome,
        "--headless=new",
        "--remote-debugging-port=0",
        "--user-data-dir=#{@profile}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--disable-background-networking",
        "--disable-sync",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--force-color-profile=srgb",
        "--font-render-hinting=none",
        "--disable-lcd-text",
        "--disable-features=NetworkService,TranslateUI,BackForwardCache",
        "--mute-audio",
        # --disable-gpu turns WebGL off entirely, which is right for the layout
        # and CSS gates this session was written for — software GL is slow and
        # rasterises text differently. It is wrong for a surface made of WebGL:
        # MapLibre and the MASTER face both measured as an empty canvas, so a
        # gate asserting "the map draws" would have passed or failed for reasons
        # that had nothing to do with the map. SwiftShader is the opt-in.
        *(@webgl ? [ "--use-angle=swiftshader", "--enable-unsafe-swiftshader" ] : [ "--disable-gpu" ]),
        "about:blank",
      ]
      unless @host_map.empty?
        rules = @host_map.map { |host, target| "MAP #{host} #{target}" }.join(", ")
        args.insert(-2, "--host-resolver-rules=#{rules}")
      end
      spawn(*args, out: File::NULL, err: File::NULL)
    end

    def devtools_port
      port_file = File.join(@profile, "DevToolsActivePort")
      deadline = monotonic + @timeout
      loop do
        if File.file?(port_file)
          line = File.read(port_file).lines.first.to_s.strip
          return line.to_i if line.to_i.positive?
        end
        raise Timeout, "Chrome never wrote DevToolsActivePort" if monotonic > deadline

        sleep 0.05
      end
    end

    def discover_page_target
      port = devtools_port
      deadline = monotonic + @timeout
      loop do
        body = begin
          Net::HTTP.get(URI("http://127.0.0.1:#{port}/json/list"))
        rescue StandardError # scan: intentional — one poll in the discovery loop; nil retries
          nil
        end
        if body
          targets = JSON.parse(body) rescue []
          page = targets.find { |t| t["type"] == "page" && t["webSocketDebuggerUrl"] }
          return page["webSocketDebuggerUrl"] if page
        end
        raise Timeout, "no CDP page target on port #{port}" if monotonic > deadline

        sleep 0.05
      end
    end

    def connect(ws_url)
      uri = URI(ws_url)
      @socket = TCPSocket.new(uri.host, uri.port)
      key = Base64.strict_encode64(SecureRandom.bytes(16))
      request = [
        "GET #{uri.request_uri} HTTP/1.1",
        "Host: #{uri.host}:#{uri.port}",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Key: #{key}",
        "Sec-WebSocket-Version: 13",
        "", ""
      ].join("\r\n")
      @socket.write(request)

      header = +""
      header << @socket.readpartial(1) until header.end_with?("\r\n\r\n")
      raise Error, "websocket handshake failed: #{header.lines.first}" unless header.start_with?("HTTP/1.1 101")

      expected = Base64.strict_encode64(Digest::SHA1.digest(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
      accept = header[/Sec-WebSocket-Accept:\s*(\S+)/i, 1]
      raise Error, "websocket accept mismatch" unless accept == expected
    end

    def enable_domains
      send_cmd("Page.enable")
      send_cmd("Runtime.enable")
      send_cmd("Network.enable")
      send_cmd("Log.enable")
    end

    # A desync poisons the read stream, not the browser. Rebuilding the
    # WebSocket to the same Chrome resyncs it and the run continues — otherwise
    # one bad frame turns into every remaining surface reporting "Desync",
    # which is a wall of noise hiding a single transport hiccup.
    def send_cmd(method, **params)
      dispatch(method, params)
    rescue Desync, Timeout => e
      raise e if @recovering || !@desync || @recoveries >= MAX_RECOVERIES

      recover!
      dispatch(method, params)
    end

    def dispatch(method, params)
      @id += 1
      id = @id
      payload = JSON.generate(params.empty? ? { id: id, method: method } : { id: id, method: method, params: params })
      write_frame(payload)
      await_response(id, method)
    end

    def recover!
      @recovering = true
      @recoveries += 1
      begin
        @socket&.close
      rescue StandardError # scan: intentional — teardown; the socket is closing either way
        nil
      end
      @desync = false
      @mid_frame = false
      @pending.clear
      @events.clear
      connect(discover_page_target)
      enable_domains
      @boot_scripts.each { |source| dispatch("Page.addScriptToEvaluateOnNewDocument", source: source) }
      Kernel.warn "  [cdp] rebuilt the DevTools connection after a desync (#{@recoveries}/#{MAX_RECOVERIES})"
    ensure
      @recovering = false
    end

    def await_response(id, method)
      deadline = monotonic + @timeout
      loop do
        if (cached = @pending.delete(id))
          return unwrap(cached, method)
        end

        remaining = deadline - monotonic
        raise Timeout, "CDP timeout: #{method}" if remaining <= 0

        message = read_message(remaining)
        next unless message

        if message["id"]
          if message["id"] == id
            return unwrap(message, method)
          else
            @pending[message["id"]] = message
          end
        else
          @events << message
          @events.shift while @events.length > 500
        end
      end
    end

    def unwrap(message, method)
      if (err = message["error"])
        raise Error, "CDP #{method}: #{err["message"]}"
      end

      message["result"] || {}
    end

    def read_message(timeout)
      frame = read_frame(timeout)
      return nil unless frame

      JSON.parse(frame)
    rescue JSON::ParserError
      nil
    end

    # --- websocket framing --------------------------------------------------

    def write_frame(payload)
      bytes = payload.b
      header = [0x81].pack("C")
      len = bytes.bytesize
      header += if len < 126
                  [0x80 | len].pack("C")
                elsif len < 65_536
                  [0x80 | 126, len].pack("Cn")
                else
                  [0x80 | 127, len].pack("CQ>")
                end
      mask = SecureRandom.bytes(4)
      masked = bytes.bytes.each_with_index.map { |b, i| b ^ mask.getbyte(i % 4) }.pack("C*")
      @socket.write(header + mask + masked)
    end

    def read_frame(timeout)
      deadline = monotonic + timeout
      buffer = +""
      loop do
        opcode, payload = read_single_frame(deadline)
        return nil unless opcode

        case opcode
        when 0x9 # ping -> pong
          write_control(0xA, payload)
          next
        when 0xA # pong
          next
        when 0x8
          raise Error, "websocket closed by browser"
        when 0x0
          buffer << payload
        else
          buffer = payload
        end
        return buffer if @frame_fin
      end
    end

    def read_single_frame(deadline)
      raise Desync, "socket abandoned mid-frame by an earlier timeout" if @desync

      @mid_frame = false
      first = read_exactly(2, deadline)
      return [nil, nil] unless first

      # Past this point every read is draining a frame the peer has committed
      # to sending, so read_exactly must not abandon it.
      @mid_frame = true
      b0 = first.getbyte(0)
      b1 = first.getbyte(1)
      @frame_fin = (b0 & 0x80) != 0
      opcode = b0 & 0x0F
      masked = (b1 & 0x80) != 0
      len = b1 & 0x7F
      len = read_exactly(2, deadline).unpack1("n") if len == 126
      len = read_exactly(8, deadline).unpack1("Q>") if len == 127
      if len > MAX_FRAME_BYTES
        @desync = true
        raise Desync, "implausible frame length #{len} — the read stream is out of sync"
      end
      mask = masked ? read_exactly(4, deadline) : nil
      payload = len.zero? ? +"" : read_exactly(len, deadline)
      if mask && payload
        payload = payload.bytes.each_with_index.map { |b, i| b ^ mask.getbyte(i % 4) }.pack("C*")
      end
      [opcode, payload.to_s]
    end

    # A timeout partway through a frame leaves the socket positioned inside a
    # message. Every later read then parses payload bytes as a header, which is
    # how a length of several exabytes gets requested. Mark the session dead the
    # moment that can have happened.
    # Waiting for a response to *begin* and waiting for a frame already in
    # flight to *finish* are different situations. Giving up on the first is
    # fine. Giving up on the second leaves the socket parked inside a message,
    # and every later read then parses payload bytes as a header — which is how
    # a length of several exabytes gets requested and the runner dies with
    # NoMemoryError instead of one surface failing.
    #
    # So: the caller's deadline governs the wait for the first byte; after that
    # a bounded grace window is granted to drain the frame, and only if the peer
    # goes silent mid-frame is the session marked unusable.
    FRAME_GRACE_SECONDS = 30

    def read_exactly(count, deadline)
      out = +""
      graced = false
      while out.bytesize < count
        remaining = deadline - monotonic
        if remaining <= 0 || !IO.select([@socket], nil, nil, [remaining, 0.0].max)
          started = !out.empty? || @mid_frame
          if started && !graced
            graced = true
            deadline = monotonic + FRAME_GRACE_SECONDS
            next
          end
          @desync = true if started
          raise Timeout, "websocket read timeout#{started ? " mid-frame" : ""}"
        end

        chunk = @socket.read_nonblock(count - out.bytesize, exception: false)
        if chunk.nil?
          @desync = true
          raise Desync, "browser closed the socket mid-message"
        end
        next if chunk == :wait_readable

        out << chunk
      end
      out
    end

    def write_control(opcode, payload)
      bytes = payload.to_s.b
      mask = SecureRandom.bytes(4)
      masked = bytes.bytes.each_with_index.map { |b, i| b ^ mask.getbyte(i % 4) }.pack("C*")
      @socket.write([0x80 | opcode, 0x80 | bytes.bytesize].pack("CC") + mask + masked)
    end
  end
end
