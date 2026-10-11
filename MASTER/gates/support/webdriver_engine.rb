# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "socket"

module Deploy
  module CaptureEngine
    # A W3C WebDriver browser: safaridriver for WebKit, geckodriver for
    # Firefox. Both ship with, or beside, the browser, so nothing is installed
    # and nothing is downloaded; when the driver or the browser is missing, or
    # the browser refuses remote automation, `open` raises Unavailable.
    #
    # WebDriver sets a window size, not a device: there is no touch or mobile
    # emulation, so a "mobile" WebKit capture is a narrow desktop Safari window.
    class WebDriverEngine < Base
      SAFARIDRIVER = %w[/usr/bin/safaridriver /System/Cryptexes/App/usr/bin/safaridriver].freeze
      GECKODRIVER = %w[/opt/homebrew/bin/geckodriver /usr/local/bin/geckodriver].freeze
      FIREFOX_APPS = ["/Applications/Firefox.app/Contents/MacOS/firefox"].freeze
      BOOT_SECONDS = 8

      def self.safari
        driver = SAFARIDRIVER.find { |path| File.executable?(path) }
        new(name: "webkit", driver:, caps: { browserName: "safari" }, missing: driver ? nil : "safaridriver not found")
      end

      def self.firefox
        driver = which("geckodriver") || GECKODRIVER.find { |path| File.executable?(path) }
        browser = FIREFOX_APPS.find { |path| File.executable?(path) } || which("firefox")
        missing = driver.nil? ? "geckodriver not found" : browser.nil? ? "firefox not found" : nil
        caps = { browserName: "firefox", "moz:firefoxOptions": { args: ["-headless"] } }
        new(name: "firefox", driver:, caps:, missing:)
      end

      def self.which(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, command) }.find { |path| File.executable?(path) }
      end

      def initialize(name:, driver:, caps:, missing: nil)
        @name = name
        @driver = driver
        @caps = caps
        @missing = missing
      end

      def open
        raise Unavailable, @missing if @missing || @driver.nil?

        @port = free_port
        @pid = Process.spawn(@driver, "-p", @port.to_s, out: File::NULL, err: File::NULL)
        wait_for_driver
        reply = post("/session", capabilities: { alwaysMatch: @caps })
        @session = reply.dig("value", "sessionId")
        raise Unavailable, "#{@name} refused a session: #{reply.dig("value", "message").to_s[0, 120]}" unless @session

        self
      rescue Unavailable
        close
        raise
      rescue StandardError => e
        close
        raise Unavailable, "#{@name} would not start: #{e.class} #{e.message[0, 100]}"
      end

      def close
        post_quietly("/session/#{@session}", method: :delete) if @session
        Process.kill("TERM", @pid) if @pid
        Process.wait(@pid) if @pid
      rescue SystemCallError
        nil
      ensure
        @session = @pid = nil
      end

      # The window includes browser chrome, so the size is corrected once by
      # what the page reports as its inner size.
      def viewport(width, height, mobile: false)
        set_window(width, height)
        inner = evaluate("[window.innerWidth, window.innerHeight]")
        set_window(width + (width - inner[0]), height + (height - inner[1])) if inner.is_a?(Array) && inner != [width, height]
      end

      def navigate(url)
        command("/url", url:)
        sleep 0.4
        url
      end

      def evaluate(js)
        command("/execute/sync", script: "return (#{js});", args: [])["value"]
      end

      def screenshot(path)
        File.binwrite(path, Base64.decode64(get("/screenshot").fetch("value")))
        path
      end

      private

      def set_window(width, height) = command("/window/rect", width:, height:)
      def command(path, **body) = post("/session/#{@session}#{path}", **body)
      def get(path) = request(Net::HTTP::Get.new("/session/#{@session}#{path}"))

      def post(path, method: :post, **body)
        req = (method == :delete ? Net::HTTP::Delete : Net::HTTP::Post).new(path, "Content-Type" => "application/json")
        req.body = JSON.generate(body)
        request(req)
      end

      def post_quietly(path, **opts)
        post(path, **opts)
      rescue StandardError
        nil
      end

      def request(req)
        res = Net::HTTP.start("127.0.0.1", @port, open_timeout: 5, read_timeout: 30) { |http| http.request(req) }
        JSON.parse(res.body.to_s)
      end

      def free_port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }

      def wait_for_driver
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + BOOT_SECONDS
        loop do
          return if TCPSocket.new("127.0.0.1", @port).close.nil?
        rescue SystemCallError
          raise "driver never listened" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

          sleep 0.1
        end
      end
    end
  end
end
