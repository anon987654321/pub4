# frozen_string_literal: true

# Verified chord cells from Röyksopp's Melody A.M. era, used as harmonic source
# material for an original Dilla live arrangement. No melodies, recordings or
# original production are reproduced here.
module Royksopp
  SOURCES = {
    remind_me: {
      title: "Remind Me",
      chords: %w[Dm7 Am7 Ebmaj7 Bb],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
    shes_so: {
      title: "She's So",
      chords: %w[Dm7 Gm7 Ebmaj7 Abmaj7],
      source: "Chordify transcription; Melody A.M.",
    },
    so_easy_c_minor: {
      title: "So Easy / C-minor section",
      chords: %w[Cm Bb Dm],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
    so_easy_a_minor: {
      title: "So Easy / A-minor section",
      chords: %w[Am G Bm],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
    so_easy_e_minor: {
      title: "So Easy / E-minor section",
      chords: %w[Em Bm D],
      source: "Musicnotes/Cifra Club transcriptions; Melody A.M.",
    },
  }.freeze

  # A live suite, not the original arrangements: each verified progression is
  # given room to breathe while the Dilla engine changes patches, bass and drums.
  SUITE = [
    *SOURCES[:remind_me][:chords],
    *SOURCES[:remind_me][:chords],
    *SOURCES[:shes_so][:chords],
    *SOURCES[:shes_so][:chords],
    *SOURCES[:so_easy_c_minor][:chords],
    *SOURCES[:so_easy_a_minor][:chords],
    *SOURCES[:so_easy_e_minor][:chords],
  ].freeze

  # Upper chord tones plus a doubled root keep the pads four-note and lush while
  # preserving the written harmony: no added ninths or altered tones.
  VOICINGS = {
    m7: [3, 7, 10, 12],
    maj7: [4, 7, 11, 12],
    maj: [4, 7, 12, 16],
  }.freeze

  NOTE_PC = {
    "C" => 0, "Db" => 1, "C#" => 1, "D" => 2, "Eb" => 3, "D#" => 3,
    "E" => 4, "F" => 5, "Gb" => 6, "F#" => 6, "G" => 7, "Ab" => 8,
    "G#" => 8, "A" => 9, "Bb" => 10, "A#" => 10, "B" => 11,
  }.freeze

  module_function

  def chord(symbol)
    m = symbol.to_s.match(/\A([A-G](?:b|#)?)(m7|maj7|m|maj)?\z/) or raise ArgumentError, "bad Röyksopp chord #{symbol.inspect}"
    root = NOTE_PC.fetch(m[1])
    quality = (m[2] || "maj").to_sym
    { symbol: symbol.to_s, root_pc: root, tones: VOICINGS.fetch(quality).map { |interval| (root + interval) % 12 } }
  end

  def source_for(symbol)
    key = SOURCES.find { |_name, row| row[:chords].include?(symbol.to_s) }&.first
    key ? SOURCES.fetch(key) : nil
  end

  def source_titles
    SOURCES.values.map { |row| row[:title] }.uniq
  end
end
