# frozen_string_literal: true

require "vips"

require "json"
require "fileutils"
require_relative "../../postpro/uncanny"

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
        # autorot, or every phone photograph is measured sideways.
        #
        # A JPEG carries the sensor's raw pixels plus an EXIF Orientation tag
        # saying how to turn them. Viewers apply it; vips hands back what is
        # actually stored. Four of these sources are orientation=6 — rotate 90 —
        # so without this they were measured as landscape when they are portrait,
        # and written into the dataset on their side. A LoRA trained on that
        # learns a sideways face.
        image = Vips::Image.new_from_file(path, access: :random).autorot
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

    # Every image paired with a caption, and every caption with an image.
    #
    # ai-toolkit resolves a caption by stripping the extension and appending
    # caption_ext, then falls through `default.txt`, a configured default, and
    # finally to the empty string — `dataloader_mixins.py` get_caption_item,
    # last branch. A missing caption is therefore not an error there; it is an
    # uncaptioned training image, and train.yaml already sets
    # caption_dropout_rate: 0.08, so some captions are deliberately empty and
    # the accidental ones do not stand out in a log.
    #
    # The other direction matters too and is what actually happened here: images
    # deleted from a prepared set by hand left their .txt files behind. Those are
    # harmless to the trainer, which enumerates images, and they are the visible
    # symptom of the edit that may also have broken a pair.
    #
    # This is what makes a filename scheme a free choice. The trainer never
    # reads the name, so hashes and readable stems are equally safe — as long as
    # the two halves of a pair still agree, which is the thing worth checking
    # rather than the thing worth naming carefully.
    def self.pairing_problems(dir, caption_ext: ".txt")
      images = Dir[File.join(dir, "*.{jpg,jpeg,png,webp}")].map { |f| File.basename(f, ".*") }
      captions = Dir[File.join(dir, "*#{caption_ext}")].map { |f| File.basename(f, caption_ext) }

      problems = []
      (images - captions).sort.each do |stem|
        problems << "#{stem}: image with no #{caption_ext} — it would train as an empty caption, silently"
      end
      (captions - images).sort.each do |stem|
        problems << "#{stem}#{caption_ext}: caption with no image — left behind when the image was removed"
      end
      empty = captions.select do |stem|
        path = File.join(dir, "#{stem}#{caption_ext}")
        File.file?(path) && File.read(path).strip.empty?
      end
      empty.sort.each { |stem| problems << "#{stem}#{caption_ext}: empty — same effect as no caption at all" }
      problems
    end

    # A stub is a caption that was written by prepare() and never edited. It is
    # not an error and cannot be one — the token is right and the rest is left
    # blank on purpose — but a set that goes to training entirely unedited has
    # had no human judgement applied to the one field that carries meaning.
    def self.unedited_captions(dir, token:, caption_ext: ".txt")
      stub = caption_stub(token).strip
      Dir[File.join(dir, "*#{caption_ext}")].select { |path| File.read(path).strip == stub }
                                            .map { |path| File.basename(path) }.sort
    rescue StandardError
      []
    end

    # Make the set consistent in the ways that help, and NOT in the way that
    # looks like it should.
    #
    # A subject LoRA learns whatever is constant across its training images.
    # That is the whole mechanism, and it is why grading a dataset to a single
    # film look is the one piece of "massaging" that must not happen: run all
    # eight through postpro and the model learns that Ragnhild IS lifted blacks
    # and Portra grain, welded to her face and impossible to ask for less of
    # later. Light, colour, background, framing and expression should vary as
    # widely as the set allows — the variation is what forces the model to
    # isolate the person from everything around her.
    #
    # What SHOULD be consistent is the part that carries no information about
    # her: exposure and white balance. Measured across this set, brightness ran
    # 75 to 146 — a 1.9x spread — and channel spread ran 2.2 to 58.7. A model
    # trained on that learns "dark" and "orange" as attributes of the subject
    # exactly as readily as it learns her face, because nothing in the data
    # distinguishes a property of the person from a property of the exposure.
    #
    # So: correct toward the SET'S OWN MEDIAN rather than toward any external
    # target. A median is drawn from these photographs, so the correction
    # cannot introduce a look that was not already the set's centre — it pulls
    # the outliers in rather than moving everyone somewhere new.
    #
    # Both corrections are clamped and the cast one is partial. A photograph
    # taken under tungsten IS warm, and flattening that to neutral would erase
    # a real property of the light and make the set duller than the truth. The
    # aim is to stop the extremes teaching a colour, not to white-balance
    # everything into a studio.
    EXPOSURE_CLAMP = 1.45
    CAST_CORRECTION = 0.6
    CAST_CLAMP = 1.25
    # Below this channel spread, the colour is left exactly as shot.
    #
    # Exposure is corrected on every image because brightness carries nothing
    # about the subject. Colour is not, and the first version of this corrected
    # it everywhere — which pulled the two genuinely neutral photographs in the
    # set from a spread of 2.2 and 4.9 up to 16.6 and 18.8, adding a warm cast
    # to pictures that did not have one, in the name of consistency.
    #
    # That is backwards. Colour variety is a subject LoRA's friend: the more the
    # light differs between frames, the harder the model has to work to separate
    # the person from the room, and the cleaner the learned identity. Only a
    # cast strong enough to become an attribute of the face is a problem.
    #
    # Measured as a RATIO spread, not a spread in levels, because levels
    # conflate cast with exposure. A dark photograph and a bright one with the
    # same colour of light report very different channel spreads: this set's
    # frame 06 read 27.7 against 10's 44.0 and looked much cleaner, and the only
    # difference was that 06 is dark. Scaled by its own mean it reads 0.37
    # against 0.41 — nearly as cast, which matches what it looks like.
    #
    # It also has to be exposure-invariant for a second reason. Exposure is
    # corrected first, and multiplying every channel by 1.4 multiplies the gap
    # between them by 1.4 too, so a threshold in levels moves under the
    # correction applied just before it. Measured in ratios the test gives the
    # same answer before and after.
    #
    # 0.35 comes from this set: 0.02, 0.05, 0.17, 0.28, 0.30, 0.37, 0.40, 0.41.
    CAST_TOLERANCE = 0.35

    Normalisation = Struct.new(:name, :exposure_gain, :channel_gains, keyword_init: true)

    def self.normalise(paths, into:)
      FileUtils.mkdir_p(into)
      stats = paths.map { |path| measure_for_normalise(path) }
      target_luma = median(stats.map { |s| s[:luma] })
      target_ratio = (0..2).map { |ch| median(stats.map { |s| s[:ratios][ch] }) }

      paths.each_with_index.map do |path, index|
        stat = stats[index]
        exposure = clamp(target_luma / stat[:luma], EXPOSURE_CLAMP)
        gains =
          if stat[:spread] <= CAST_TOLERANCE
            [1.0, 1.0, 1.0]
          else
            (0..2).map do |ch|
              full = target_ratio[ch] / stat[:ratios][ch]
              clamp(1.0 + (full - 1.0) * CAST_CORRECTION, CAST_CLAMP)
            end
          end

        image = Vips::Image.new_from_file(path, access: :random).autorot
        out = image.cast(:float).bandsplit.first(3).each_with_index.map do |band, ch|
          band * (exposure * gains[ch])
        end
        dest = File.join(into, File.basename(path))
        Vips::Image.bandjoin(out).cast(:uchar).write_to_file("#{dest}[Q=95]")

        Normalisation.new(name: File.basename(path), exposure_gain: exposure, channel_gains: gains)
      end
    end

    def self.measure_for_normalise(path)
      image = Vips::Image.new_from_file(path, access: :random).autorot
      means = image.bandsplit.first(3).map(&:avg)
      luma = image.colourspace("b-w").avg
      # Ratios rather than absolute channel means, so exposure and white balance
      # are corrected independently instead of one soaking up the other.
      grey = means.sum / 3.0
      ratios = means.map { |m| [m / grey, 0.01].max }
      { luma: [luma, 1.0].max, ratios: ratios, spread: ratios.max - ratios.min }
    end

    def self.median(values)
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    def self.clamp(value, limit) = value.clamp(1.0 / limit, limit)

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

    # `<subject>/dataset`, and named here because `into:` had no default and the
    # first set prepared by this file went to `dataset_1024` — a directory no
    # lane reads. `_toolkit/lib.sh` and `run_train_kaggle.rb` both resolve
    # `SUBJECT_DIR/dataset` and nothing resolves anything else, so a set written
    # anywhere else is invisible: the Kaggle lane reported "dataset missing" for
    # a dataset that was sitting beside the directory it looked in.
    #
    # The short edge belongs in TRAIN_SHORT_EDGE, not in the directory name.
    # Encoding it there invites one directory per resolution and leaves every
    # lane guessing which is current.
    DATASET_DIRNAME = "dataset"

    # A caption stub, not an invented caption. The subject token has to be exact
    # and is knowable; everything after it describes what is IN the picture,
    # which is not measurable from pixels. A guessed caption teaches the wrong
    # word, and the guidance says to edit every one rather than trust
    # automation.
    #
    # One definition because two readers need to agree on it: prepare() writes
    # it, and unedited_captions() recognises it to report which captions nobody
    # has touched. Written out twice, an edit to the wording in one place would
    # have made the other silently report zero unedited captions.
    def self.caption_stub(token) = "#{token}, woman, "

    def self.dataset_dir(subject_dir) = File.join(subject_dir, DATASET_DIRNAME)

    def self.prepare(candidates, into:, token:, short_edge: TRAIN_SHORT_EDGE)
      FileUtils.mkdir_p(into)
      candidates.each_with_index.map do |candidate, index|
        image = Vips::Image.new_from_file(candidate.path, access: :random).autorot
        current = [image.width, image.height].min
        out_image = image.resize(short_edge.to_f / current)

        name = format("a_photo_of_%s_%02d", token, index + 1)
        out = File.join(into, "#{name}.jpg")
        out_image.write_to_file("#{out}[Q=95]")

        File.write(File.join(into, "#{name}.txt"), caption_stub(token))

        { name: name, from: File.basename(candidate.path),
          was: "#{image.width}x#{image.height}",
          now: "#{out_image.width}x#{out_image.height}",
          upscaled: current < short_edge }
      end
    end
  end
end
