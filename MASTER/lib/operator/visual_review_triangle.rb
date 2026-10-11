# frozen_string_literal: true

require "net/http"
require "rbconfig"

module Operator
  # Boots the local apps a review needs and takes down exactly the ones it
  # started. An app that answered /up before the review began is somebody
  # else's and is never stopped.
  class VisualReviewTriangle
    TOOL = File.expand_path("../../tools/rails/triangle.rb", __dir__)
    BOOT_SECONDS = 1200

    attr_reader :started

    # ports: app name => port. runner: ->(args) { [output, success] }.
    def initialize(ports:, runner: nil, probe: nil)
      @ports = ports
      @runner = runner || method(:run_tool)
      @probe = probe || method(:listening?)
      @started = []
    end

    # Returns the apps still down after the attempt.
    def ensure_up(apps)
      wanted = Array(apps).uniq.select { |app| @ports[app] }
      down = wanted.reject { |app| @probe.call(@ports[app]) }
      unless down.empty?
        @started |= down
        @runner.call(["up", *down])
      end
      wanted.reject { |app| @probe.call(@ports[app]) }
    end

    def release
      return [] if @started.empty?

      stopped = @started
      @runner.call(["down", *stopped])
      @started = []
      stopped
    end

    private

    def run_tool(args)
      out, status = Master::Io::Exec.capture2e(RbConfig.ruby, TOOL, *args, timeout: BOOT_SECONDS)
      [out, status.success?]
    end

    def listening?(port)
      response = Net::HTTP.start("127.0.0.1", port, open_timeout: 2, read_timeout: 4) { |http| http.get("/up") }
      response.code.to_i.between?(200, 399)
    rescue StandardError
      false
    end
  end
end
