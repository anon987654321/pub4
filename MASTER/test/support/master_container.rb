# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Master
  module TestSupport
    # Boots a sandboxed MASTER instance rooted at a tmpdir with fixture YAMLs.
    # Yields the infra hash; cleans up on exit.
    #
    # Usage:
    #   with_master_container do |m|
    #     m[:gateway].receive(channel: :cli, message: "/help")
    #     assert m[:trace].pretty_last
    #   end
    module Container
      DEFAULT_FIXTURES = {
        "soul.yml" => <<~YML,
          version: "test"
          persona: anchor
          absolute:
            golden_rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK
            rules:
              FAIL_VISIBLY: never rescue Exception silently.
              SIMPLEST_WORKS: refuse god classes.
              PRESERVE_FIRST: read first. preserve behavior. larger changes allowed if safe.
              BE_CONCISE: minimal response.
          negotiable:
            style: openbsd_dmesg
            default_model: openrouter/auto
        YML
        "personas.yml" => <<~YML,
          anchor:
            voice: en-US-AndrewNeural
            tts_rate: "-8%"
            tts_pitch: "+8Hz"
            style: clear
            description: "Norwegian. Clear. Curious."
        YML
        "voice.yml" => <<~YML,
          tts:
            single_voice: osman
            neural: ms-MY-OsmanNeural
            persona_affects_text_only: true
          voice:
            strunk:
              preambles: []
              hedges: []
              endings: []
        YML
        "rules.yml" => <<~YML,
          rules: {}
          voice:
            strunk: { preambles: [], endings: [] }
            banned_output: []
          thresholds:
            class: { max_lines: 200, max_methods: 6 }
        YML
        "limits.yml" => "{}\n",
      }.freeze

      def with_master_container(extra_fixtures: {}, env: {})
        root = Dir.mktmpdir("master_container_")
        begin
          FileUtils.mkdir_p(File.join(root, "data"))
          FileUtils.mkdir_p(File.join(root, ".master"))
          DEFAULT_FIXTURES.merge(extra_fixtures).each do |name, body|
            File.write(File.join(root, "data", name), body)
          end
          original_env = env.keys.to_h { |k| [k, ENV[k]] }
          env.each { |k, v| ENV[k] = v.to_s }
          begin
            infra = Master::Builder.build(root:)
            yield infra
          ensure
            original_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
          end
        ensure
          FileUtils.rm_rf(root) if root && Dir.exist?(root)
        end
      end
    end
  end
end
