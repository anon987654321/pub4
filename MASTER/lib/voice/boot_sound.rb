# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Master
  module Voice
    # The startup sound, "Lysbue": an Fmaj9 FM pad swells in under an opening lowpass, then one or two crushed
    # FM bells ring on top, in a short room with tape wow and hiss. The score is data in voice.yml under
    # boot_sound; this renders it per surface (cli, web) into a stereo wav cached outside the repo. The terminal
    # plays it when a session starts and the face plays the same render, built into public/ with the assets.
    # Every onset is a raised cosine and the bells never open the sound, because a hard onset is what startles.
    # MASTER_BOOT_SOUND=0 or `enabled: false` is silence; it never plays without a terminal.
    module BootSound

      RATE = Dsp::RATE
      TAU = Dsp::TAU

      # Joins the cache key, so a changed renderer never replays a file the old one wrote.
      ENGINE = 2

      module_function

      def config = Policy.section("boot_sound")

      def enabled?(settings = config)
        return false if ENV["MASTER_BOOT_SOUND"] == "0" || ENV["MASTER_SKIP_TTS"] == "1" || ENV["CI"]

        settings["enabled"] == true && $stdout.tty?
      end

      # Plays the terminal's render in the background. True when a player was started.
      def play(settings = config)
        return false unless enabled?(settings)

        player = settings.fetch("player").to_s.split
        return false unless Master::Voice::Playback.which(player.first)

        path = ensure_wav(settings, surface: :cli)
        argv = [*player.map { |word| format(word, volume: settings.fetch("volume", 1.0)) }, path]
        pid = Process.spawn(*argv, **Master::Io::ProcessSpawn.options(out: File::NULL, err: File::NULL, pgroup: true))
        Process.detach(pid)
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::BootSound.play")
        false
      end

      def ensure_wav(settings = config, surface: :cli)
        path = File.join(Dir.home, ".master", "boot_sound", "chime_#{cache_key(settings, surface:)}.wav")
        return path if File.size?(path)

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, wav(render(settings, surface:)))
        path
      end

      # Every setting that shapes the sound, the surface and the engine. Only the switch, the player and its
      # volume stay out, because they change how the file is played and not what is in it.
      def cache_key(settings, surface: :cli)
        material = { engine: ENGINE, surface: surface.to_s, settings: settings.except("enabled", "player", "volume") }
        Digest::SHA256.hexdigest(JSON.generate(material))[0, 12]
      end

      def surface_settings(settings, surface) = settings.fetch("surfaces").fetch(surface.to_s)

      def seconds(surface = :cli, settings = config) = surface_settings(settings, surface).fetch("seconds")

      # The file the face fetches. Its name carries the cache key, so a build that has not rendered this
      # score answers 404 and the face stays quiet rather than playing a stale sound.
      def asset_name(settings = config) = "boot_sound_#{cache_key(settings, surface: :web)}.ogg"

      def browser_payload(settings = config)
        return { url: nil } unless settings["enabled"] == true

        web = surface_settings(settings, :web)
        { url: asset_name(settings), late_gesture_s: web.fetch("late_gesture_s"),
          fade_ms: settings.dig("master", "fade_in_ms") }
      end

      # [left, right], scaled so the louder channel peaks at the surface's ceiling_dbfs.
      def render(settings, surface: :cli)
        shape = surface_settings(settings, surface)
        pad = notes_for(settings, shape:, layer: "pad")
        stereo = mix(settings, pad:, bells: notes_for(settings, shape:, layer: "bells"),
                               frames: (shape.fetch("seconds") * RATE).round)

        stereo = Dsp.room(stereo, settings.fetch("room"))
        stereo = Dsp.tape(stereo, settings.fetch("tape"), swell: pad.first.fetch("attack_ms") / 1000.0)
        Dsp.normalise(Dsp.master(stereo, settings.fetch("master")), shape.fetch("ceiling_dbfs"))
      end

      # The pad goes through the lowpass sweep; the bells bypass it.
      def mix(settings, pad:, bells:, frames:)
        swept = bus(pad, frames).map { |channel| Dsp.lowpass_sweep(channel, settings.fetch("filter")) }
        swept.zip(bus(bells, frames)).map { |one, other| one.zip(other).map(&:sum) }
      end

      # A layer's notes over its defaults, with the surface's overrides between the two: a surface key
      # named "<layer>_<field>" sets that field, and one named after the layer keeps only that many notes.
      def notes_for(settings, shape:, layer:)
        defaults = settings.fetch(layer)
        base = defaults.except("notes").merge(surface_overrides(shape, layer))
        notes = defaults.fetch("notes").map { |note| base.merge(note) }
        notes.first(shape.fetch(layer, notes.size))
      end

      def surface_overrides(shape, layer)
        prefix = "#{layer}_"
        shape.filter_map { |key, value| [key.delete_prefix(prefix), value] if key.start_with?(prefix) }.to_h
      end

      def bus(notes, frames)
        out = [Array.new(frames, 0.0), Array.new(frames, 0.0)]

        notes.each_with_index do |note, order|
          note.fetch("copies", [{}]).each do |copy|
            voiced = note.merge(copy)
            pan_into(out, voice(voiced, frames:, order:), pan: voiced.fetch("pan", 0.5))
          end
        end
        out
      end

      # Equal-power pan, 0 hard left and 1 hard right.
      def pan_into(out, mono, pan:)
        left = Math.cos(pan * Math::PI / 2)
        right = Math.sin(pan * Math::PI / 2)
        mono.each_with_index do |sample, i|
          out[0][i] += sample * left
          out[1][i] += sample * right
        end
      end

      # One two-operator FM voice over the whole render, silent before its onset. The phases accumulate,
      # so the wow bends the pitch without a glitch.
      def voice(note, frames:, order: 0)
        out = oscillate(plan(note, order), frames)
        note["crush"] ? crushed(out, note) : out
      end

      def oscillate(plan, frames)
        out = Array.new(frames, 0.0)
        carrier = modulator = 0.0

        (plan[:start]...frames).each do |i|
          step = frequency(plan, i.to_f / RATE) / RATE
          carrier += step
          modulator += step * plan[:ratio]
          out[i] = sample(plan, (i - plan[:start]).to_f / RATE, carrier:, modulator:)
        end
        out
      end

      def crushed(samples, note)
        Dsp.hold(samples.map { |sample| Dsp.crush(sample, note.fetch("crush_bits")) }, note.fetch("hold", 1))
      end

      def sample(plan, seconds, carrier:, modulator:)
        tone = Math.sin((TAU * carrier) + (index_at(plan, seconds) * Math.sin(TAU * modulator)))
        tone * envelope(plan, seconds) * plan[:gain]
      end

      def plan(note, order)
        onset = (note.fetch("at_ms") + note.fetch("shift_ms", 0)) / 1000.0
        release_at = note["release_at_ms"] ? (note["release_at_ms"] / 1000.0) - onset : 0.0
        { start: (onset * RATE).round, onset:, order:, note:, release_at:,
          freq: midi_hz(note.fetch("midi")) * cents(note.fetch("detune_cents", 0)),
          ratio: note.fetch("ratio"), gain: note.fetch("gain"), wow: note["wow"] }
      end

      def midi_hz(midi) = 440.0 * (2.0**((midi - 69) / 12.0))

      def cents(amount) = 2.0**(amount / 1200.0)

      def frequency(plan, absolute)
        wow = plan[:wow]
        return plan[:freq] unless wow

        plan[:freq] * cents(wow.fetch("cents") * Math.sin((TAU * wow.fetch("hz") * absolute) + plan[:order]))
      end

      # A raised-cosine rise over attack_ms, a hold, then an exponential release with a time constant of
      # release_ms from release_at_ms; without release_at_ms the release starts at the onset, as a bell's does.
      def envelope(plan, seconds)
        note = plan[:note]
        rise = Dsp.raised_cosine(seconds * 1000.0 / note.fetch("attack_ms"))
        after = seconds - plan[:release_at]
        after.positive? ? rise * Math.exp(-after * 1000.0 / note.fetch("release_ms")) : rise
      end

      # The modulation index, which sets the brightness. With index_peak it swells from index_from to the
      # peak over index_ms and falls to index_to over index_fall_ms, as a brass note does; without it, it
      # decays from index_from toward index_to with a time constant of index_ms, as a bell does.
      def index_at(plan, seconds)
        note = plan[:note]
        span = note.fetch("index_ms") / 1000.0
        return brass_index(note, seconds:, span:) if note["index_peak"]

        to = note.fetch("index_to")
        to + ((note.fetch("index_from") - to) * Math.exp(-seconds / span))
      end

      def brass_index(note, seconds:, span:)
        from = note.fetch("index_from")
        peak = note.fetch("index_peak")
        fall = Dsp.raised_cosine((seconds - span) * 1000.0 / note.fetch("index_fall_ms"))
        from + ((peak - from) * Dsp.raised_cosine(seconds / span)) - ((peak - note.fetch("index_to")) * fall)
      end

      def wav(channels)
        count = channels.size

        pcm = channels.first.each_index.flat_map { |i| channels.map { |ch| (ch[i] * 32_767).round } }.pack("s<*")
        header = ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, count, RATE, RATE * 2 * count, 2 * count, 16,
                  "data", pcm.bytesize]
        header.pack("a4Va4a4VvvVVvva4V") + pcm
      end
    end
  end
end
