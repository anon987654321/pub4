# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Deploy
  # The browser as a process: where Chrome is, how it is launched, how its
  # debugging port is discovered, and how it is reaped.
  #
  # Split out when cdp_session.rb passed its file-length ceiling a second time.
  # The first split took the RFC 6455 half into cdp_framing.rb; this is the
  # other seam in the same file — everything left in CdpSession speaks the
  # DevTools Protocol to a browser that is already running, and nothing here
  # knows what CDP is.
  #
  # Timeout is spelled CdpSession::Timeout throughout. Bare `Timeout` resolves
  # to the stdlib module, and it resolves at the moment the deadline is hit —
  # a NameError instead of the error the caller rescues. That is the failure
  # cdp_framing.rb's own comment records from the first split.
  module ChromeProcess
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

    # Asked of the class, because every rendered suite gates on
    # CdpSession.available? before it considers spawning anything.
    module Discovery
      def chrome_path
        CHROME_PATHS.find { |path| File.executable?(path) }
      end

      def available?
        !chrome_path.nil?
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
        raise CdpSession::Timeout, "Chrome never wrote DevToolsActivePort" if monotonic > deadline

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
        raise CdpSession::Timeout, "no CDP page target on port #{port}" if monotonic > deadline

        sleep 0.05
      end
    end
  end
end
