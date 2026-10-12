# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"

module Contracts
  module Studio
    PHOTOGRAPH_TIMEOUT = Integer(ENV.fetch("STUDIO_PHOTOGRAPH_TIMEOUT", "120"))
    HEAR_DRUMS_TIMEOUT = Integer(ENV.fetch("STUDIO_HEAR_DRUMS_TIMEOUT", "1500"))
    HEAR_DRUMS_MAX_SECONDS = 120

    module_function

    def root
      value = ENV["PUB4_STUDIO_ROOT"].to_s.strip
      return File.expand_path(value) unless value.empty?

      File.expand_path("../../STUDIO", __dir__)
    end

    def dilla_script = first_file("dilla/dilla.rb")
    def photograph_script = first_file("photograph.rb")
    def postpro_script = first_file("postpro/postpro.rb")
    def replicate_script = first_file("replicate/replicate.rb")
    def sonic_reference = first_file("dilla/data/reference_sonic.yml")

    def first_file(relative)
      path = File.join(root, relative)
      File.file?(path) ? path : nil
    end

    def photograph(prompt:, film: false, duration: 5)
      script = photograph_script or raise "STUDIO photograph entrypoint is unavailable"
      argv = [RbConfig.ruby, script]
      argv << "--film" if film
      argv.concat(["--duration", duration.to_i.to_s, prompt.to_s])
      output, status = run_bounded(argv, chdir: root)
      raise "STUDIO photograph failed: #{output.lines.last.to_s.strip}" unless status.success?

      JSON.parse(output)
    end

    # MASTER decides whether a source may be heard and what it may cost; STUDIO
    # hears it. The result is believed only when STUDIO reports status "ok" with
    # a dossier carrying the evidence the contract requires -- an exit code or a
    # missing report never reads as success.
    def hear_drums(source:, authorized: false, allow_network: false, artist: nil, style_tags: [], max_seconds: 60)
      return refused("authorization required: the operator must confirm the right to analyze this source") unless authorized == true
      return refused("max_seconds must be an integer from 1 to #{HEAR_DRUMS_MAX_SECONDS}") unless max_seconds.is_a?(Integer) && max_seconds.between?(1, HEAR_DRUMS_MAX_SECONDS)
      return refused("source must be a non-empty string") unless source.is_a?(String) && !source.strip.empty?
      return refused("network source requires allow_network") if source.match?(%r{\A[a-z][a-z0-9+.-]*://}i) && allow_network != true
      return refused("style_tags must be an array") unless style_tags.is_a?(Array)

      script = dilla_script or return unavailable("STUDIO dilla entrypoint is unavailable")
      source = File.expand_path(source.strip) unless source.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
      argv = [RbConfig.ruby, script, "hear-drums", source,"--max-seconds", max_seconds.to_s]
      argv.push("--artist", artist.to_s) if artist
      argv.push("--style", style_tags.join(",")) unless style_tags.empty?
      output, status = run_bounded(argv, chdir: root, timeout: HEAR_DRUMS_TIMEOUT)
      hear_drums_result(output, status)
    end

    def hear_drums_result(output, status)
      line = output.to_s.lines.reverse.find { |l| l.start_with?("{") }
      result = line && JSON.parse(line)
      return failed("dispatch", "STUDIO produced no report (exit #{status.exitstatus.inspect})") unless result.is_a?(Hash)
      return failed(result["stage"], result["reason"], result) unless status.success? && result["status"] == "ok"

      dossier = result["dossier"]
      evidence = dossier.is_a?(Hash) && %w[source_hash stem_hashes tools drum_pattern engine_hints style_tags].all? { |k| dossier.key?(k) }
      return failed("dispatch", "STUDIO reported ok without a complete dossier") unless evidence

      { "status" => "ok", "capability" => "available", "dossier_path" => result["dossier_path"], "dossier" => dossier }
    rescue JSON::ParserError
      failed("dispatch", "STUDIO report was not valid JSON")
    end

    def refused(reason) = { "status" => "refused", "stage" => "policy", "reason" => reason }

    def unavailable(reason) = { "status" => "failed", "stage" => "dispatch", "reason" => reason, "capability" => "unavailable: #{reason}" }

    def failed(stage, reason, result = {})
      capability = result["kind"] == "tool_unavailable" ? "unavailable: #{reason}" : "degraded: #{reason}"
      { "status" => "failed", "stage" => stage, "reason" => reason, "capability" => capability, "diagnostics" => result["diagnostics"] }.compact
    end

    def run_bounded(argv, chdir:, timeout: PHOTOGRAPH_TIMEOUT)
      output = +""
      status = nil

      Open3.popen2e(*argv, chdir:) do |stdin, io, wait|
        stdin.close
        reader = Thread.new { output = io.read.to_s }

        unless wait.join(timeout)
          begin
            Process.kill("TERM", wait.pid)
          rescue Errno::ESRCH
          end

          unless wait.join(5)
            begin
              Process.kill("KILL", wait.pid)
            rescue Errno::ESRCH
            end
            wait.join
          end
        end

        reader.join
        status = wait.value
      end

      [output, status]
    end
  end
end
