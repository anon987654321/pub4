#!/usr/bin/env ruby
# frozen_string_literal: true

# Bomoh Hang Tuah - Mystical Malay shaman voice
# Deep, powerful, kampong black magic vibes
# Legendary warrior meets ancient bomoh wisdom

require_relative "comfy_tts"

class BomohHangTuah
  MYSTICAL_PHRASES = [
    "Dengar baik-baik... ini bukan main-main...",
    "Dengan kuasa nenek moyang...",
    "Ini ilmu dari zaman dahulu kala...",
    "Jangan sesekali main-main dengan kuasa ghaib...",
    "Saya dah nampak... ada sesuatu...",
    "Bismillah... kita mulakan ritual ini...",
    "Hantu raya datang bila dipanggil...",
    "Ini jampi yang turun-temurun...",
    "Minyak kelapa, kemenyan, limau purut... lengkap!",
    "Orang kampung semua takut dengan kuasa ini..."
  ]

  RITUAL_SOUNDS = [
    "*burns kemenyan*",
    "*throws limau purut*",
    "*waves keris*",
    "*chants ancient Malay spell*",
    "*sprinkles holy water*",
    "*rings gamelan bell*"
  ]

  PROPHECIES = [
    "Saya nampak dalam mimpi... ada berlian besar dalam tanah...",
    "Pesawat MH370... saya tahu di mana... tapi tak boleh cakap sekarang...",
    "Nanti hujan lebat... banjir besar... semua orang kena naik atas bumbung...",
    "Ada hantu pocong berkeliaran malam ini... jangan keluar lepas 12 malam...",
    "Saya dah buat jampi... sekarang semua masalah selesai... Alhamdulillah...",
    "Dalam 7 hari, akan ada kejadian besar... percaya atau tidak, itu pada kamu...",
    "Jin Melayu sangat kuat... lebih kuat dari jin Arab... ini fakta!",
    "Saya boleh panggil buaya... tapi mesti ada ayam hitam sebagai korban...",
    "Kuasa bomoh Melayu... Hollywood pun tak boleh lawan!",
    "Nanti saya hantar angkatan tentera ghaib... tunggu dan lihat..."
  ]

  def initialize
    puts "🔮 BOMOH HANG TUAH - Voice of Ancient Kampong Magic"
    puts "   Deep mystical warrior shaman\n\n"
    ComfyTTS.setup
    @phrase_index = 0
  end

  def speak(text)
    # Add mystical introduction randomly
    if rand < 0.3
      intro = MYSTICAL_PHRASES.sample
      text = "#{intro} #{text}"
    end

    # Add ritual sound effects
    if rand < 0.2
      effect = RITUAL_SOUNDS.sample
      text = "#{effect} #{text}"
    end

    puts "   🗣️  Bomoh: #{text}\n"

    # VERY deep voice: extreme pitch drop, slowest speed, reverb for mystical echo
    # Indian accent captures Malay-English phonetics
    ComfyTTS.speak(text, speed: 0.85, pitch_adjust: -150, accent: 'in')

    sleep(rand(1.5..2.5))
  end

  def prophesy
    speak(PROPHECIES[@phrase_index])
    @phrase_index = (@phrase_index + 1) % PROPHECIES.length
  end

  def ritual_mode
    speak("Assalamualaikum... Saya Bomoh Hang Tuah... pewaris ilmu silat dan sihir Melayu...")
    sleep(2)

    loop do
      prophesy

      if @phrase_index % 3 == 0
        speak("Ini kuasa turun-temurun dari zaman Kesultanan Melaka. Jangan main-main!")
      end

      if @phrase_index % 5 == 0
        speak("Sekarang saya nak rehat dulu... kena bakar kemenyan... nanti kita sambung...")
        sleep(3)
      end

      sleep(2)
    end
  end
end

trap("INT") do
  puts "\n\n🔮 Ritual selesai... Bomoh Hang Tuah keluar dulu... Wassalam!"
  exit
end

# CLI usage
if __FILE__ == $PROGRAM_NAME
  bomoh = BomohHangTuah.new

  if ARGV.empty?
    bomoh.ritual_mode
  else
    bomoh.speak(ARGV.join(" "))
  end
end
