# frozen_string_literal: true

require "shellwords"
require "yaml"
require_relative "../boot/paths"
require_relative "../result"
require_relative "script_dispatch"

module Master
  module Io
    # Plain-language requests for the person-LoRA tooling in STUDIO/lora:
    # "generate me a selfie", "train a lora of ragnhild", "make a video with the
    # lora of me", "lora status".
    #
    # Recognition, the subjects and the spending gate are data (data/lora.yml).
    # This module turns a sentence into one argv for STUDIO/lora/lora.rb and runs
    # it through ScriptDispatch. Anything that spends money (a render, a training,
    # a clip) runs as a dry run unless the sentence also confirms it, so a request
    # is always safe to say and the plan is always shown first.
    module LoraIntent
      module_function

      REGEXP_OPTIONS = Regexp::IGNORECASE
      IMAGE_EXTENSIONS = %w[jpg jpeg png webp].freeze
      NUMBER_WORDS = %w[zero one two three four five six seven eight nine ten].freeze
      PAID = %i[selfie train video].freeze

      def handles?(text) = !intent_for(text, config).nil?

      def dispatch(text, root: MasterPaths.root)
        cfg = config
        intent = intent_for(text, cfg)
        return Result.err("lora: not a lora request", category: :validation) unless intent

        subject = subject_for(text, cfg) unless intent == :status
        return subject if subject.is_a?(Result) && !subject.ok?

        name = subject&.value!
        confirmed = confirmed?(text, cfg)
        built = build(intent, text, name, cfg, root:)
        return built unless built.ok?

        run(intent, built.value!, name, confirmed:, root:)
      end

      def config = YAML.safe_load_file(File.join(MasterPaths.root, "data", "lora.yml"))

      def pattern(cfg, key) = Regexp.new(cfg.fetch(key), REGEXP_OPTIONS)

      # The first declared intent that matches wins. An intent may need an
      # action word ("make", "lag") and a context ("video" alone is not a LoRA
      # request), both from the data file.
      def intent_for(text, cfg)
        cfg.fetch("intents").each do |spec|
          next unless text.match?(Regexp.new(spec.fetch("match"), REGEXP_OPTIONS))
          next if spec["context"] && !text.match?(Regexp.new(spec["context"], REGEXP_OPTIONS))
          next if spec.fetch("needs_action", true) && !text.match?(pattern(cfg, "action"))

          return spec.fetch("name").to_sym
        end
        nil
      end

      NEGATED_CONFIRMATION = /\b(?:don't|dont|do not|never|not|no|without)\b.{0,32}\b(?:confirm(?:ed)?|for real|go ahead|bekreft\w*|kj[øo]r\s+p[åa]\s+ordentlig)\b/i.freeze

      def confirmed?(text, cfg)
        return false if text.match?(NEGATED_CONFIRMATION)

        text.match?(pattern(cfg, "confirm"))
      end

      # Named subjects win over "me". Two names in one request is refused: a
      # render, a training and a clip each belong to one person.
      def subject_for(text, cfg)
        named = cfg.fetch("subjects").select do |_, spec|
          spec.fetch("names").any? { |name| text.match?(/\b#{Regexp.escape(name)}/i) }
        end.keys
        return Result.err("lora: one person per request, you named #{named.join(' and ')}", category: :validation) if named.size > 1
        return Result.ok(named.first) if named.size == 1

        Result.ok(cfg.fetch("me"))
      end

      def build(intent, text, subject, cfg, root: MasterPaths.root)
        case intent
        when :status then Result.ok(["--status"])
        when :train then Result.ok(["--subject", subject, "--train-replicate"])
        when :selfie then Result.ok(selfie_args(text, subject, cfg))
        when :video then video_args(text, subject, cfg, root:)
        end
      end

      def selfie_args(text, subject, cfg)
        sittings = (1..cfg.fetch("selfie_sittings")).to_a.sample(selfie_count(text, cfg)).sort
        args = ["--subject", subject, "--generate-replicate", "--set", "selfies", "--only", sittings.join(",")]
        args << "--draft" if text.match?(pattern(cfg, "draft"))
        args
      end

      def selfie_count(text, cfg)
        word = text[/\b(\d+|#{NUMBER_WORDS.drop(1).join('|')})\s+(?:\w+\s+)?selfies\b/i, 1]
        count = word ? (word.match?(/\A\d+\z/) ? word.to_i : NUMBER_WORDS.index(word.downcase)) : nil
        count ||= text.match?(/\bselfies\b/i) ? cfg.fetch("selfie_batch") : 1
        count.clamp(1, cfg.fetch("selfie_max"))
      end

      # The still a clip starts from: a path in the sentence, else the newest
      # graded selfie, else the newest ungraded one.
      def video_args(text, subject, cfg, root: MasterPaths.root)
        image = image_from(text, root:) || latest_selfie(subject)
        unless image
          return Result.err("lora: no selfie of #{subject} to animate yet; say \"generate me a selfie\" first, " \
                            "or give a path to a still", category: :validation)
        end

        preset = video_preset(text, cfg)
        Result.ok(["--subject", subject, "--video-replicate", "--image", image, "--prompt", video_prompt(text, subject, cfg),
                   "--preset", preset])
      end

      def image_from(text, root: MasterPaths.root)
        extensions = IMAGE_EXTENSIONS.join("|")
        path = text[/["']([^"']+\.(?:#{extensions}))["']/i, 1] || text[/(\S+\.(?:#{extensions}))\b/i, 1]
        return unless path

        bases = [root, MasterPaths.repo, Dir.pwd].compact.map { |base| File.expand_path(base.to_s) }.uniq
        bases.each do |base|
          candidate = File.expand_path(path, base)
          return candidate if File.file?(candidate)
        end
        nil
      end

      def latest_selfie(subject)
        out = File.join(MasterPaths.repo, "STUDIO", "lora", subject, "out")
        %w[selfies_postpro selfies].each do |dir|
          files = Dir[File.join(out, dir, "*.{#{IMAGE_EXTENSIONS.join(',')}}")]
          return files.max_by { |file| File.mtime(file) } unless files.empty?
        end
        nil
      end

      def video_preset(text, cfg)
        return "kling" if text.match?(pattern(cfg, "kling"))

        text.match?(pattern(cfg, "final")) ? "final" : "draft"
      end

      # Motion the sentence names ("... where she turns and smiles"), else the
      # default for the subject's pronoun.
      def video_prompt(text, subject, cfg)
        spoken = text[/\b(?:where|that|showing|so that|in which)\s+(.+?)[.!?]?\z/i, 1]
        if spoken
          options = [cfg.fetch("draft"), cfg.fetch("final"), cfg.fetch("kling"), cfg.fetch("confirm")].join("|")
          spoken = spoken.sub(/\s*,?\s*(?:#{options})\s*\z/i, "").strip
          return spoken unless spoken.empty?
        end

        format(cfg.fetch("video_prompt"), he: cfg.fetch("subjects").fetch(subject).fetch("pronoun"))
      end

      # A paid request without confirmation is run as --dry-run; a confirmed
      # training is started async, since it runs far longer than a chat turn.
      def run(intent, args, subject, confirmed:, root:)
        paid = PAID.include?(intent)
        args += confirmed ? (intent == :train ? ["--async"] : []) : ["--dry-run"] if paid
        result = ScriptDispatch.run(root:, tool: "lora", arg: Shellwords.join(args))
        return result unless result.ok?

        dry = paid && !confirmed
        Result.ok(output: report(intent, result.value!, subject, dry:), rendered: result.value!, media: :"lora_#{intent}",
                  subject:, dry_run: dry)
      end

      def report(intent, output, subject, dry:)
        return output unless dry

        "#{output}\n\nDry run for #{subject} (#{intent}); nothing was spent. " \
          "Say the same thing with \"confirm\" to run it for real."
      end
    end
  end
end
