# frozen_string_literal: true

require "json"
require "fileutils"

# Composition spine for dilla.rb — memory, arrangement, performers, tension,
# critique, scoring, evolution, and session persistence.
module DillaComposition
  PROJECT_DIR = ENV.fetch("DILLA_PROJECT_DIR", File.join(File.expand_path("..", __dir__), "project"))
  SESSION_PATH = File.join(PROJECT_DIR, "session.json")
  MOTIFS_PATH = File.join(PROJECT_DIR, "motifs.json")
  HISTORY_PATH = File.join(PROJECT_DIR, "history.json")

  ARRANGEMENT_FORM = %i[intro verse hook verse bridge solo breakdown hook outro].freeze

  ARRANGEMENT_PROFILES = {
    intro:     { drums: 0.42, harmony: 0.62, lead: 0.08, bass: 0.55, swing_delta: -4, stereo: 0.35, saturation: 0.12, melodic_density: 0.2, fill_rate: 0.1 },
    verse:     { drums: 0.72, harmony: 0.92, lead: 0.32, bass: 0.78, swing_delta: 0, stereo: 0.55, saturation: 0.22, melodic_density: 0.45, fill_rate: 0.25 },
    hook:      { drums: 0.92, harmony: 1.0, lead: 0.82, bass: 0.88, swing_delta: 3, stereo: 0.78, saturation: 0.35, melodic_density: 0.75, fill_rate: 0.55 },
    bridge:    { drums: 0.58, harmony: 0.78, lead: 0.48, bass: 0.65, swing_delta: -2, stereo: 0.62, saturation: 0.28, melodic_density: 0.55, fill_rate: 0.35 },
    solo:      { drums: 0.68, harmony: 0.72, lead: 0.95, bass: 0.62, swing_delta: 5, stereo: 0.85, saturation: 0.4, melodic_density: 0.9, fill_rate: 0.45 },
    breakdown: { drums: 0.28, harmony: 0.55, lead: 0.12, bass: 0.42, swing_delta: -6, stereo: 0.4, saturation: 0.1, melodic_density: 0.15, fill_rate: 0.05 },
    outro:     { drums: 0.38, harmony: 0.48, lead: 0.18, bass: 0.5, swing_delta: -3, stereo: 0.45, saturation: 0.14, melodic_density: 0.22, fill_rate: 0.12 }
  }.freeze

  ENSEMBLE_TIMELINE = {
    intro:     %i[ep],
    verse:     %i[ep warm],
    hook:      %i[ep warm lead scale_lead],
    bridge:    %i[ep texture warm],
    solo:      %i[ep lead scale_lead],
    breakdown: %i[warm texture],
    outro:     %i[ep warm]
  }.freeze

  PERFORMERS = {
    yancey: {
      name: "James Yancey", kick_lag_ms: 8, snare_early_ms: -18, hat_late_ms: 22,
      velocity_spread: 0.14, gate_mul: 0.88, ghost_boost: 1.15
    },
    questlove: {
      name: "Questlove", kick_lag_ms: 2, snare_early_ms: -8, hat_late_ms: 6,
      velocity_spread: 0.08, gate_mul: 0.95, ghost_boost: 1.35
    },
    chris_dave: {
      name: "Chris Dave", kick_lag_ms: 14, snare_early_ms: -12, hat_late_ms: 28,
      velocity_spread: 0.18, gate_mul: 0.72, ghost_boost: 1.5
    },
    karriem: {
      name: "Karriem Riggins", kick_lag_ms: 5, snare_early_ms: -14, hat_late_ms: 12,
      velocity_spread: 0.11, gate_mul: 0.9, ghost_boost: 1.25
    },
    glasper: {
      name: "Robert Glasper", kick_lag_ms: 4, snare_early_ms: -6, hat_late_ms: 10,
      velocity_spread: 0.1, gate_mul: 1.08, ghost_boost: 0.95
    },
    herbie: {
      name: "Herbie Hancock", kick_lag_ms: 3, snare_early_ms: -4, hat_late_ms: 8,
      velocity_spread: 0.09, gate_mul: 1.12, ghost_boost: 0.88
    },
    thundercat: {
      name: "Thundercat", kick_lag_ms: 10, snare_early_ms: -10, hat_late_ms: 18,
      velocity_spread: 0.12, gate_mul: 0.82, ghost_boost: 1.1
    },
    dilla: { name: "Dilla default", kick_lag_ms: 6, snare_early_ms: -12, hat_late_ms: 14,
             velocity_spread: 0.1, gate_mul: 0.92, ghost_boost: 1.2 }
  }.freeze

  GROOVE_DNA = {
    donuts: {
      kick_offset_ms: [0, 6, 12, 18, 24], hat_offset_ms: [8, 14, 20, 26],
      swing: 61, ghost_density: 1.25, velocity_curve: [0.42, 0.52, 0.48, 0.58]
    },
    fantastic_vol2: {
      kick_offset_ms: [0, 4, 10, 16], hat_offset_ms: [6, 12, 18],
      swing: 58, ghost_density: 1.1, velocity_curve: [0.48, 0.55, 0.5, 0.6]
    },
    endtroducing: {
      kick_offset_ms: [0, 8, 14], hat_offset_ms: [10, 18, 24],
      swing: 54, ghost_density: 0.85, velocity_curve: [0.4, 0.46, 0.44, 0.5]
    },
    madvillainy: {
      kick_offset_ms: [0, 5, 11, 20], hat_offset_ms: [7, 15, 22],
      swing: 63, ghost_density: 1.4, velocity_curve: [0.5, 0.62, 0.55, 0.65]
    },
    cosmogramma: {
      kick_offset_ms: [0, 10, 18, 26], hat_offset_ms: [12, 20, 28],
      swing: 66, ghost_density: 1.15, velocity_curve: [0.44, 0.52, 0.5, 0.56]
    }
  }.freeze

  class MotifCell
    attr_reader :id, :degrees, :rhythm, :state

    STATES = %i[A A_prime A_double_prime].freeze

    def initialize(id:, degrees:, rhythm: [1.0, 0.5, 0.5, 1.0], state: :A)
      @id = id
      @degrees = degrees
      @rhythm = rhythm
      @state = state
    end

    def evolve!
      idx = STATES.index(@state) || 0
      @state = STATES[[idx + 1, STATES.length - 1].min]
      self
    end

    def degrees_for_playback
      case @state
      when :A then @degrees
      when :A_prime then @degrees.map { |d| d + 1 }
      when :A_double_prime then @degrees.reverse + @degrees.first(2)
      else @degrees
      end
    end

    def to_h
      { id: @id, degrees: @degrees, rhythm: @rhythm, state: @state.to_s }
    end

    def self.parse_state(raw)
      sym = raw.to_s.to_sym
      return sym if STATES.include?(sym)
      case raw.to_s
      when "A", "a" then :A
      when "A_prime", "A'", "a_prime" then :A_prime
      when "A_double_prime", "A''", "a_double_prime" then :A_double_prime
      else :A
      end
    end

    def self.from_h(h)
      new(id: h["id"] || h[:id], degrees: h["degrees"], rhythm: h["rhythm"] || [1.0, 0.5, 0.5, 1.0],
          state: parse_state(h["state"] || h[:state] || "A"))
    end
  end

  class Session
    attr_accessor :track, :performer, :groove_dna, :generation, :best_score
    attr_reader :motifs, :callbacks, :tension_curve, :critique_log, :arrangement

    def initialize(track: "timeless", performer: :yancey, groove_dna: :donuts, n_bars: 64)
      @track = track
      @performer = performer.to_sym
      @groove_dna = groove_dna.to_sym
      @generation = 0
      @best_score = 0.0
      @motifs = []
      @callbacks = []
      @critique_log = []
      @arrangement = build_arrangement(n_bars)
      @tension_curve = build_tension_curve(n_bars)
      seed_motifs!
    end

    def build_arrangement(n_bars)
      bars_per = (n_bars.to_f / ARRANGEMENT_FORM.length).ceil.clamp(4, 32)
      plan = []
      bar = 0
      ARRANGEMENT_FORM.each do |section|
        bars_per.times do
          break if bar >= n_bars
          plan << { bar: bar, section: section }
          bar += 1
        end
      end
      while bar < n_bars
        plan << { bar: bar, section: :verse }
        bar += 1
      end
      plan
    end

    def build_tension_curve(n_bars)
      # Intro low → verse rise → hook peak → bridge dip → solo climb → breakdown valley → outro fade
      anchors = [0.18, 0.35, 0.72, 0.4, 0.55, 0.88, 0.32, 0.22]
      curve = []
      n_bars.times do |b|
        pos = b.to_f / [n_bars - 1, 1].max
        ai = pos * (anchors.length - 1)
        i0 = ai.floor
        i1 = [i0 + 1, anchors.length - 1].min
        frac = ai - i0
        curve << (anchors[i0] * (1 - frac) + anchors[i1] * frac).round(4)
      end
      curve
    end

    def seed_motifs!
      return unless @motifs.empty?
      rng = Random.new(@track.to_s.hash.abs)
      hook = MotifCell.new(id: "hook", degrees: [0, 2, 1, 3].first(rng.rand(3..4)),
                           rhythm: [1.0, 0.5, 0.5, 1.0])
      bass = MotifCell.new(id: "bass_motif", degrees: [0, 0, 2, 1], rhythm: [1.0, 1.0, 0.5, 0.5])
      @motifs = [hook, bass]
      @callbacks = [{ bar: 0, motif_id: "hook", state: :A },
                    { bar: 16, motif_id: "hook", state: :A_prime },
                    { bar: 32, motif_id: "hook", state: :A_double_prime },
                    { bar: 48, motif_id: "hook", state: :A_prime }]
    end

    def section_at(bar)
      entry = @arrangement.find { |e| e[:bar] == bar }
      entry ? entry[:section] : :verse
    end

    def profile_at(bar)
      ARRANGEMENT_PROFILES[section_at(bar)] || ARRANGEMENT_PROFILES[:verse]
    end

    def tension_at(bar)
      @tension_curve[bar.clamp(0, @tension_curve.length - 1)] || 0.5
    end

    def motif_for_bar(bar)
      cb = @callbacks.select { |c| c[:bar] <= bar }.max_by { |c| c[:bar] }
      return nil unless cb
      m = @motifs.find { |mot| mot.id == cb[:motif_id] }
      return m unless m
      MotifCell.new(id: m.id, degrees: m.degrees, rhythm: m.rhythm, state: cb[:state])
    end

    def performer_profile
      PERFORMERS[@performer] || PERFORMERS[:dilla]
    end

    def groove_profile
      GROOVE_DNA[@groove_dna] || GROOVE_DNA[:donuts]
    end

    def ensemble_roles(section = nil)
      section ||= :verse
      ENSEMBLE_TIMELINE[section] || ENSEMBLE_TIMELINE[:verse]
    end

    def record_callback!(bar, motif_id, state)
      @callbacks << { bar: bar, motif_id: motif_id, state: state }
      m = @motifs.find { |mot| mot.id == motif_id }
      m&.evolve!
    end

    def mutate!(rng: Random.new(@generation + 1))
      @generation += 1
      @performer = PERFORMERS.keys.sample(random: rng)
      @groove_dna = GROOVE_DNA.keys.sample(random: rng)
      @motifs.each { |m| m.evolve! if rng.rand < 0.4 }
      @tension_curve = @tension_curve.map { |t| (t + rng.rand(-0.08..0.08)).clamp(0.05, 0.98).round(4) }
      self
    end

    def save!
      FileUtils.mkdir_p(PROJECT_DIR)
      payload = {
        track: @track, performer: @performer.to_s, groove_dna: @groove_dna.to_s,
        generation: @generation, best_score: @best_score,
        motifs: @motifs.map(&:to_h), callbacks: @callbacks.map { |c| c.transform_values(&:to_s) },
        tension_curve: @tension_curve,
        arrangement: @arrangement.map { |e| e.transform_values(&:to_s) },
        critique_log: @critique_log.last(20)
      }
      File.write(SESSION_PATH, JSON.pretty_generate(payload) + "\n")
      File.write(MOTIFS_PATH, JSON.pretty_generate(@motifs.map(&:to_h)) + "\n")
      payload
    end

    def self.load!(default_track: "timeless", n_bars: 64)
      return new(track: default_track, n_bars: n_bars) unless File.exist?(SESSION_PATH)
      data = JSON.parse(File.read(SESSION_PATH))
      s = new(track: data["track"] || default_track, performer: (data["performer"] || "yancey").to_sym,
              groove_dna: (data["groove_dna"] || "donuts").to_sym, n_bars: n_bars)
      s.instance_variable_set(:@generation, data["generation"] || 0)
      s.instance_variable_set(:@best_score, data["best_score"] || 0.0)
      s.instance_variable_set(:@motifs, (data["motifs"] || []).map { |h| MotifCell.from_h(h) })
      s.instance_variable_set(:@callbacks, (data["callbacks"] || []).map do |c|
        h = c.transform_keys(&:to_sym)
        { bar: h[:bar].to_i, motif_id: h[:motif_id].to_s,
          state: MotifCell.parse_state(h[:state]) }
      end)
      s.instance_variable_set(:@tension_curve, data["tension_curve"] || s.build_tension_curve(n_bars))
      s.instance_variable_set(:@critique_log, data["critique_log"] || [])
      s
    end
  end

  module Counterpoint
    module_function

    def parallel_fifth?(prev_intervals, next_intervals)
      return false if prev_intervals.nil? || next_intervals.nil?
      prev_intervals.zip(next_intervals).any? do |a, b|
        a && b && (a - b).abs < 0.01 && [7, 12].include?((a % 12).round)
      end
    end

    def adjust_voices(voices_hz)
      sorted = voices_hz.sort
      return sorted if sorted.length < 2
      out = sorted.dup
      (1...out.length).each do |i|
        out[i] = [out[i], out[i - 1] * 1.059].max if (out[i] - out[i - 1]).abs < 1.0
      end
      out
    end

    def neighbor_tone(root_hz, direction: :up)
      semitone = direction == :up ? 2.0**(2.0 / 12.0) : 2.0**(-2.0 / 12.0)
      root_hz * semitone
    end

    def passing_tone(from_hz, to_hz, step: 0.5)
      from_hz + (to_hz - from_hz) * step
    end
  end

  module Conversation
    module_function

    # Returns offset seconds for answering voice per layer role.
    def answer_offset(role, beat_p)
      case role
      when :ep then beat_p * 0.5
      when :lead then beat_p * 1.0
      when :bass then beat_p * 0.25
      when :warm then beat_p * 2.0
      else beat_p * 0.75
      end
    end

    def turn_order(bar)
      %i[ep warm bass lead].rotate(bar % 4)
    end
  end

  module Critique
    module_function

    def analyze(report, session: nil, events: nil)
      lufs = report[:integrated_lufs] || report["integrated_lufs"]
      groove = score_groove(events)
      harmony = 72 + (session ? 8 : 0)
      hook = session ? hook_score(session) : 55
      variation = session ? variation_score(session) : 50
      stereo = report.dig(:spectral_rms_db, :high) ? 88 : 75
      scores = { groove: groove, harmony: harmony, hook: hook, variation: variation, stereo: stereo, lufs: lufs_score(lufs) }
      recs = recommendations(scores, session)
      { scores: scores, recommendations: recs, overall: (scores.values.compact.sum / scores.length).round(1) }
    end

    def score_groove(events)
      return 70 unless events
      kicks = events[:kick]&.length || 0
      ghosts = events[:ghost]&.length || 0
      (60 + [kicks * 0.5, 20].min + [ghosts * 0.3, 15].min).round.clamp(40, 98)
    end

    def hook_score(session)
      states = session.callbacks.map { |c| c[:state] }.uniq.length
      (50 + states * 12 + session.motifs.length * 5).clamp(30, 95)
    end

    def variation_score(session)
      (45 + session.generation * 3 + session.tension_curve.uniq.length * 0.5).round.clamp(30, 92)
    end

    def lufs_score(lufs)
      return 70 unless lufs
      lufs = lufs.to_f
      (-14.0..-11.0).cover?(lufs) ? 95 : 65
    end

    def recommendations(scores, session)
      recs = []
      recs << "Increase hook repetition — register more A/A'/A'' callbacks." if scores[:hook] < 65
      recs << "Reduce pad masking — lower warm mix or high-pass pads in breakdown." if scores[:harmony] < 70
      recs << "Move bass entrance earlier in verse sections." if session && session.profile_at(4)[:bass] < 0.7
      recs << "Add ghost-note density for pocket." if scores[:groove] < 75
      recs << "Widen stereo image on hook — raise lead/EP pan spread." if scores[:stereo] < 80
      recs << "Target LUFS -14..-11 for delivery." if scores[:lufs] && scores[:lufs] < 80
      recs << "Track feels balanced — evolve motifs for next pass." if recs.empty?
      recs
    end

    def print_report(critique)
      puts "── Producer critique ──"
      critique[:scores].each { |k, v| puts format("%-12s %s", "#{k}:", v) }
      puts "overall: #{critique[:overall]}"
      puts "Recommendations:"
      critique[:recommendations].each { |r| puts "  • #{r}" }
    end
  end

  module Scorer
    module_function

    def score_plan(session, cfg, n_bars)
      prof = session.profile_at(n_bars / 2)
      tension = session.tension_at(n_bars / 2)
      groove = session.groove_profile[:swing] / 70.0
      novelty = session.generation * 0.02
      repetition = session.callbacks.length * 0.08
      release = session.tension_curve.each_cons(2).count { |a, b| b < a } * 0.05
      voice_lead = cfg[:progression] ? 0.15 : 0.1
      (prof[:melodic_density] * 0.25 + tension * 0.2 + groove * 0.2 + repetition * 0.15 +
       novelty * 0.1 + release * 0.1 + voice_lead).clamp(0.0, 1.0)
    end

    def pick_best(candidates)
      candidates.max_by { |c| c[:score] }
    end
  end

  module Evolution
    module_function

    def run(session:, cfg:, n_bars:, generations: 5, render_fn:)
      best = { score: -1.0, session: session, path: nil }
      generations.times do |gen|
        session.generation = gen
        session.mutate!
        score = Scorer.score_plan(session, cfg, n_bars)
        path = render_fn.call(session)
        report = render_fn.respond_to?(:quality) ? render_fn.quality(path) : {}
        critique = Critique.analyze(report, session: session)
        total = (score * 50 + critique[:overall] * 0.5).round(2)
        session.critique_log << { gen: gen, score: total, critique: critique[:scores] }
        if total > best[:score]
          best = { score: total, session: session, path: path, critique: critique }
          session.best_score = total
        end
        puts "gen #{gen}: score=#{total}"
      end
      session.save!
      best
    end
  end

  module ListeningLoop
    module_function

    def converge(render_fn:, analyze_fn:, max_passes: 3, targets: {})
      targets = { lufs_min: -14.5, lufs_max: -10.5, groove_min: 75 }.merge(targets)
      path = nil
      max_passes.times do |pass|
        path = render_fn.call(pass)
        report = analyze_fn.call(path)
        critique = Critique.analyze(report)
        lufs = report[:integrated_lufs] || report["integrated_lufs"]
        groove = critique[:scores][:groove]
        puts "pass #{pass + 1}: LUFS=#{lufs} groove=#{groove}"
        break if lufs && lufs.to_f >= targets[:lufs_min] && lufs.to_f <= targets[:lufs_max] && groove >= targets[:groove_min]
        ENV["DRUM_VOL"] = (ENV["DRUM_VOL"] || "0.3").to_f + 0.02 if groove < targets[:groove_min]
        ENV["HARM_VOL"] = (ENV["HARM_VOL"] || "2.4").to_f + 0.05 if lufs && lufs.to_f < targets[:lufs_min]
      end
      path
    end
  end
end