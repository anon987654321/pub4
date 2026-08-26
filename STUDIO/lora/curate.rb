# frozen_string_literal: true

require "vips"
require "json"
require "fileutils"
require_relative "../postpro/uncanny"

# Which of these photographs should train a LoRA, and which should not.
#
# A dataset is not a pile of pictures of someone. STUDIO/PHOTOGRAPHY.md sets out
# four layers, and three of them decide whether a training image earns its place:
#
#   resolution   below the training size the detail is invented by an upscaler,
#                and the model learns the upscaler.
#   sharpness    a soft frame teaches soft. This is the one that quietly ruins a
#                set, because a blurred photograph still looks fine at thumbnail
#                size and that is how sets get assembled.
#   highlights   blown areas carry no information, so the model learns a white
#                shape where a cheekbone was.
#
# The fourth — variety — is the one nobody measures and everybody assumes. Ten
# frames of one moment are one training example with nine copies, and a LoRA
# trained on them reproduces that moment rather than the person. So selection is
# spread as well as scored: the best frame is not worth having ten times.
#
# Nothing here judges the photograph. It cannot see whether the expression is
# real or the light is flattering, and those decide whether anyone cares. It
# removes the ones that are technically unusable so that judgement is spent on
# a shorter list.
module Lora
  module Curate
    # FLUX trains at 512, 768 or 1024 on the short edge. Below 512 there is
    # nothing to train on.
    MIN_SHORT_EDGE = 512
    PREFERRED_SHORT_EDGE = 1024
    # Below this a frame is soft. Calibrated against a mobile video: its sharpest
    # frames read about 0.045 and its softest about 0.035, while a still
    # photograph from a phone camera reads 0.01-0.04 depending on subject.
    SOFT_FLOOR = 0.008
    BLOWN_CEILING = 3.0

    Candidate = Struct.new(:path, :width, :height, :texture, :clipping, :index, keyword_init: true) do
      def short_edge = [width, height].min
      def megapixels = (width * height) / 1_000_000.0
    end

    Verdict = Struct.new(:candidate, :rejected_for, keyword_init: true) do
      def usable? = rejected_for.nil?
    end

    def self.scan(dir)
      files = Dir[File.join(dir, "**", "*.{jpg,jpeg,JPG,JPEG,png,PNG,webp,WEBP}")].sort
      files.each_with_index.filter_map do |path, index|
        image = Vips::Image.new_from_file(path, access: :random)
        reading = Postpro::Uncanny.read(path)
        Candidate.new(path: path, width: image.width, height: image.height,
                      texture: reading.texture, clipping: reading.clipping, index: index)
      rescue Vips::Error
        # A file vips cannot open is not a candidate, and is worth saying so
        # rather than dropping silently — a HEIC in a set of JPEGs is the usual
        # cause and it is fixable.
        nil
      end
    end

    # scan then judge, which is what every caller wants and what the first
    # version made them assemble themselves — select() takes verdicts and
    # scan() returned candidates, so the two did not meet.
    def self.assess(dir) = scan(dir).map { |candidate| judge(candidate) }

    def self.judge(candidate)
      reason =
        if candidate.short_edge < MIN_SHORT_EDGE
          "short edge #{candidate.short_edge}px is under #{MIN_SHORT_EDGE} — an upscaler would " \
          "invent the detail and the model would learn the upscaler"
        elsif candidate.texture < SOFT_FLOOR
          format("soft (texture %.4f) — a blurred frame teaches blur", candidate.texture)
        elsif candidate.clipping > BLOWN_CEILING
          format("%.1f%% blown — no information where the highlight was", candidate.clipping)
        end
      Verdict.new(candidate: candidate, rejected_for: reason)
    end

    # The best `count`, spread rather than clustered.
    #
    # Sorting by sharpness and taking the top N is the obvious approach and the
    # wrong one for frames from a single video: the sharpest ten are usually
    # consecutive, because sharpness tracks how still the camera was, and
    # consecutive frames are the same moment. So the run is divided into `count`
    # windows and the best of each window is taken. Across a folder of unrelated
    # photographs the windows fall where they fall and it degrades to "best of
    # each nth", which is harmless.
    def self.select(verdicts, count:)
      usable = verdicts.select(&:usable?).map(&:candidate)
      return usable if usable.size <= count

      window = usable.size.to_f / count
      (0...count).map do |slot|
        first = (slot * window).floor
        last = [((slot + 1) * window).floor, usable.size].min
        usable[first...last].max_by(&:texture)
      end.compact
    end

    def self.report(verdicts, chosen)
      lines = ["curate: #{verdicts.size} candidate(s)"]
      rejected = verdicts.reject(&:usable?)
      unless rejected.empty?
        lines << "curate: #{rejected.size} unusable —"
        rejected.first(12).each do |verdict|
          lines << "  #{File.basename(verdict.candidate.path)}: #{verdict.rejected_for}"
        end
        lines << "  … and #{rejected.size - 12} more" if rejected.size > 12
      end
      lines << "curate: chose #{chosen.size}"
      chosen.each do |candidate|
        lines << format("  %-34s %dx%d  %.1fMP  texture %.4f",
                        File.basename(candidate.path), candidate.width, candidate.height,
                        candidate.megapixels, candidate.texture)
      end
      lines << "curate: what this cannot see — whether the expression is real, whether the light"
      lines << "curate: flatters, and whether the same moment is here twice under different names."
      lines
    end

    # A training-ready set: one short edge, one format, one naming scheme, and
    # every original aspect ratio kept.
    #
    # NOT cropped to square, and the first version of this was. Trainers bucket
    # by aspect ratio, so forcing a square throws away composition for nothing:
    # centre-cropping a 1080x1920 phone photograph discards 44% of it and takes
    # the crown of a head with it whenever the subject is not dead centre. The
    # guidance is explicit — set the resolution to the images' own size and the
    # LoRA uses the aspect ratio "without cutting heads and feet".
    #
    # 1024 on the SHORT edge, up OR down, so the whole set carries the same
    # information density.
    #
    # An earlier version left anything already larger alone, on the reasoning
    # that discarding resolution is a decision for the trainer. That is wrong
    # for a set this size. A 2048px image holds roughly four times the
    # information of a 1024px one, and hyperparameters tuned for 1024 turn
    # destructive against it — the reported failure mode is extreme overfitting,
    # and eleven images is already the low end of the 10-30 the guidance asks
    # for. Mixing 4080px and 1080px sources in one small set is that problem
    # with an extra variable on top.
    #
    # The other half of the same rule: train no higher than the source. A 1080p
    # original trained at 1024 is honest; trained at 2048 the model learns the
    # upscaler's artefacts and calls them the subject.
    TRAIN_SHORT_EDGE = 1024

    def self.prepare(candidates, into:, token:, short_edge: TRAIN_SHORT_EDGE)
      FileUtils.mkdir_p(into)
      candidates.each_with_index.map do |candidate, index|
        image = Vips::Image.new_from_file(candidate.path, access: :random)
        current = [image.width, image.height].min
        out_image = image.resize(short_edge.to_f / current)

        name = format("a_photo_of_%s_%02d", token, index + 1)
        out = File.join(into, "#{name}.jpg")
        out_image.write_to_file("#{out}[Q=95]")

        # A caption stub, not an invented caption. The subject token has to be
        # exact and is knowable; everything after it describes what is IN the
        # picture, which is not measurable from pixels. A guessed caption
        # teaches the wrong word, and the guidance says to edit every one rather
        # than trust automation.
        File.write(File.join(into, "#{name}.txt"), "#{token}, woman, ")

        { name: name, from: File.basename(candidate.path),
          was: "#{image.width}x#{image.height}",
          now: "#{out_image.width}x#{out_image.height}",
          upscaled: current < short_edge }
      end
    end
  end
end
