# frozen_string_literal: true

require "json"
require "yaml"
require "rbconfig"

module Master
  module Fix
    class Wishlist
      # A wishlist proof is executable only when MASTER can name the exact
      # deterministic operation that proves it. Free-form model prose is never
      # allowed to turn an applied proposal into VERIFIED.
      module ProofContract
        module_function

        KNOWN = {
          "file exists" => :file_exists,
          "ruby syntax" => :ruby_syntax,
          "yaml parse" => :yaml_parse,
          "json parse" => :json_parse,
        }.freeze

        def normalized(value)
          value.to_s.downcase.strip.gsub(/[[:space:]]+/, " ")
        end

        def known?(value)
          KNOWN.key?(normalized(value))
        end

        def verify(proposal, root:)
          proofs = Array(proposal["proof"]).map { |value| normalized(value) }.reject(&:empty?)
          return { state: :open, checks: ["no executable proof contract"] } if proofs.empty?

          path = anchor_path(proposal["anchor"], root)
          return { state: :open, checks: ["anchor is not a file"] } unless path

          checks = proofs.map do |proof|
            kind = KNOWN[proof]
            return { state: :open, checks: ["unsupported proof: #{proof}"] } unless kind

            begin
              ok = public_send(kind, path)
              return { state: :failed, checks: ["#{proof}: failed"] } unless ok

              "#{proof}: passed"
            rescue StandardError => e
              return { state: :failed, checks: ["#{proof}: #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"] }
            end
          end

          { state: :proven, checks: }
        end

        def anchor_path(anchor, root)
          path, line = anchor.to_s.split(":", 2)
          return unless line.to_s.match?(/\A\d+\z/)

          file = File.expand_path(path, root)
          File.file?(file) && file.start_with?("#{File.expand_path(root)}#{File::SEPARATOR}") ? file : nil
        end

        def file_exists(path)
          File.file?(path)
        end

        def ruby_syntax(path)
          return false unless path.end_with?(".rb")
          system(RbConfig.ruby, "-c", path, out: File::NULL, err: File::NULL)
        end

        def yaml_parse(path)
          YAML.safe_load_file(path, aliases: false)
          true
        end

        def json_parse(path)
          JSON.parse(File.read(path, encoding: "UTF-8"))
          true
        end
      end
    end
  end
end
