# frozen_string_literal: true

class CraneTTS
  include DillaConstants

  LESSONS = {
    intro: "Yo, Professor Crane here. Today we're recreating legendary producer techniques. J Dilla's MPC three thousand. Madlib's SP four oh four. Flying Lotus on Ableton. Watch how their equipment translates to pure SoX wizardry.",
    chord_theory: "These jazz voicings come straight from Slum Village Fantastic. Minor sevenths, major sevenths, diminished chords. Stacked in thirds like Dilla programmed them. Moog style analog drift adds that vintage oscillator instability.",
    microtiming: "MPC three thousand magic right here. Kicks drift plus or minus forty milliseconds. Snares drag thirty to forty behind. That's how Dilla humanized the machine. Drunk timing. Unquantized groove.",
    swing: "Sixty-two to sixty-six percent swing. Not your basic fifty-fifty quantize. SP twelve hundred and MPC sequencer feel. Every other hit pushes late. That's pocket. That's bounce.",
    pads: "SP four oh four effects chain in action. Tape saturation. Vinyl simulator. Deep reverb like Flying Lotus runs in Ableton. Detuned oscillators create that Minimoog warmth Dilla used for basslines.",
    bass: "Walking bassline following chord roots. Not just one drone. Jazz bassist approach. Electric bass timbre with overdrive. Anchors the harmony like a proper rhythm section.",
    mix: "MPC style mixer ratios. Drums at seventy-five percent. Pads at forty-five. Bass at sixty-five. Crane Song HEDD harmonic enhancement. Triode for second harmonic warmth. Pentode for third harmonic brightness.",
    complete: "There it is. Legendary producer techniques recreated in SoX. Dilla microtiming. Madlib tape saturation. FlyLo stereo width. Proper frequency balance from Sound on Sound guidelines. That's how you make beats that breathe."
  }.freeze

  def speak(text)
    return unless text

    Thread.new do
      mp3 = fetch_tts(text)
      play_mp3(mp3) if mp3
    end
  end

  private

  def fetch_tts(text)
    hash = "#{text}en".hash.abs.to_s
    mp3 = "#{TTS_CACHE_DIR}/#{hash}.mp3"
    return mp3 if File.exist?(mp3)

    url = "https://translate.google.com/translate_tts?" \
          "ie=UTF-8&client=tw-ob&tl=en&ttsspeed=0.75&tld=com&q=#{CGI.escape(text)}"

    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "Mozilla/5.0"
      req["Referer"] = "https://translate.google.com/"
      res = http.request(req)

      if res.code == "200" && res.body.size > 1000
        File.binwrite(mp3, res.body)
        return mp3
      end
    end
    nil
  rescue
    nil
  end

  def play_mp3(file)
    return unless File.exist?(file)
    win_path = `cygpath -w "#{file}" 2>/dev/null`.chomp
    win_path = file if win_path.empty?
    system("cmd.exe /c start /min \"\" \"#{win_path}\" 2>/dev/null")
    sleep((File.size(file) / 8000.0).ceil)
  end
end
