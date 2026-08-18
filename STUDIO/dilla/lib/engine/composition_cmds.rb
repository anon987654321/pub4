# frozen_string_literal: true
#
# Composition commands: jam, evolve, critique, listen.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# =============================================================================
# COMPOSITION — memory, arrangement, performers, evolution, critique
# =============================================================================

def composition_jam(n_bars = 16)
  ENV["COMPOSITION"] = "1"
  reset_composition_session!
  n_bars = (ENV["BARS"] || n_bars).to_i
  sess = composition_session!(n_bars:, force_new: true)
  puts "jam — #{sess.track} | performer=#{sess.performer} groove=#{sess.groove_dna} | #{n_bars} bars"
  dest = File.join(SCRATCH_DIR, "jam_tmp.wav")
  render_dilla(dest, n_bars, keep_stems: true)
  play_loop(dest)
end

def composition_evolve(n_bars = 16, generations = 5)
  ENV["COMPOSITION"] = "1"
  n_bars = (ENV["BARS"] || n_bars).to_i
  generations = (ENV["GENERATIONS"] || generations).to_i
  reset_composition_session!
  sess = composition_session!(n_bars:, force_new: true)
  cfg = dilla_resolve_config
  dest = File.join(SCRATCH_DIR, "evolve_best.wav")
  render_fn = lambda do |session|
    @composition_session = session
    out = File.join(SCRATCH_DIR, "evolve_gen#{session.generation}.wav")
    render_dilla(out, n_bars, keep_stems: false)
    out
  end
  render_fn.define_singleton_method(:quality) { |path| dilla_quality(path) }
  render_fn.define_singleton_method(:last_events) { @last_drum_events }
  best = DillaComposition::Evolution.run(session: sess, cfg:, n_bars:,
                                         generations:, render_fn:)
  FileUtils.cp(best[:path], dest) if best[:path] && File.exist?(best[:path])
  DillaComposition::Critique.print_report(best[:critique]) if best[:critique]
  puts "evolve best score=#{best[:score]} → #{dest}"
  dest
end

def composition_critique(path = nil)
  path ||= File.join(SCRATCH_DIR, "live_tmp.wav")
  path = File.join(SCRATCH_DIR, "jam_tmp.wav") unless File.file?(path)
  abort "no render to critique — run: ruby dilla.rb jam" unless File.file?(path)
  report = dilla_quality(path)
  sess = composition_session!(n_bars: bars)
  critique = DillaComposition::Critique.analyze(report, session: sess, events: @last_drum_events)
  DillaComposition::Critique.print_report(critique)
  sess.critique_log << { path:, critique: critique[:scores], overall: critique[:overall] }
  sess.save!
  critique
end

def composition_session_cmd(sub = nil, *rest)
  case sub.to_s.downcase
  when "save"
    sess = composition_session!(n_bars: bars)
    payload = sess.save!
    puts "session saved → #{DillaComposition::SESSION_PATH}"
    puts JSON.pretty_generate(payload.slice("track", "performer", "groove_dna", "generation", "best_score"))
  when "load"
    reset_composition_session!
    ENV["COMPOSITION"] = "1"
    n_bars = (rest[0] || ENV["BARS"] || bars).to_i
    sess = composition_session!(n_bars:, force_new: true)
    puts "session loaded — #{sess.track} performer=#{sess.performer} groove=#{sess.groove_dna}"
  when "show", nil, ""
    sess = composition_session!(n_bars: bars)
    puts "── Session ──"
    puts "track: #{sess.track}  performer: #{sess.performer}  groove: #{sess.groove_dna}"
    puts "generation: #{sess.generation}  best_score: #{sess.best_score}"
    puts "motifs: #{sess.motifs.map { |m| "#{m.id}(#{m.state})" }.join(', ')}"
    puts "callbacks: #{sess.callbacks.length}  tension anchors: #{sess.tension_curve.length}"
    puts "arrangement: #{sess.arrangement.map { |e| e[:section] }.uniq.join(' → ')}"
  when "new"
    reset_composition_session!
    ENV["COMPOSITION"] = "1"
    track = rest[0] || ENV["TRACK"] || "timeless"
    n_bars = (rest[1] || ENV["BARS"] || bars).to_i
    @composition_session = DillaComposition::Session.new(track:, n_bars:)
    @composition_session.save!
    puts "new session — #{track} (#{n_bars} bars)"
  else
    abort "usage: ruby dilla.rb session [save|load|show|new] [args]"
  end
end

def regenerate_stem(stem, bars_count = 16)
  ENV["COMPOSITION"] = "1"
  bars_count = (ENV["BARS"] || bars_count).to_i
  sess = composition_session!(n_bars: bars_count)
  case stem.to_s.downcase
  when "bass"
    sess.motifs.find { |m| m.id == "bass_motif" }&.evolve!
  when "hats"
    keys = DillaComposition::GROOVE_DNA.keys
    sess.groove_dna = keys[(keys.index(sess.groove_dna) || 0) + 1] % keys.length
  when "melody"
    sess.motifs.find { |m| m.id == "hook" }&.evolve!
    sess.record_callback!(bars_count / 2, "hook", :A_prime)
  else
    abort "usage: ruby dilla.rb regenerate-stem bass|hats|melody [bars]"
  end
  sess.save!
  puts "regenerate-stem #{stem} — performer=#{sess.performer} groove=#{sess.groove_dna}"
  regenerate(bars_count)
end

def composition_listen_loop(n_bars = 16)
  ENV["COMPOSITION"] = "1"
  n_bars = (ENV["BARS"] || n_bars).to_i
  max_passes = (ENV["LISTEN_PASSES"] || 3).to_i
  dest = File.join(SCRATCH_DIR, "listen_loop.wav")
  render_fn = ->(pass) { render_dilla(File.join(SCRATCH_DIR, "listen_pass#{pass}.wav"), n_bars); dest }
  analyze_fn = ->(path) { dilla_quality(path) }
  path = DillaComposition::ListeningLoop.converge(render_fn:, analyze_fn:, max_passes:)
  FileUtils.cp(path, dest) if path && File.exist?(path)
  puts "listen_loop → #{dest}"
  play_loop(dest) if File.exist?(dest)
end
