# frozen_string_literal: true

class CraneTTS
  include DillaConstants

  LESSONS = {
    intro: "Good evening! I'm Professor Crane, and today we'll explore the fascinating intersection of digital signal processing and neo-soul aesthetics. Think of it as if Miles Davis met MATLAB at a dinner party!",
    swing: "Ah yes, the swing factor! You see, quantization is for amateurs. The human ear craves temporal imperfection. We're adding a sixty-two percent swing ratio - that's the rhythmic equivalent of a perfectly aged Bordeaux.",
    dm9: "Now we encounter the D minor ninth chord. Four glorious intervals stacked like a well-constructed argument: root, minor third, perfect fifth, minor seventh, and the pièce de résistance, the major ninth. This is harmonic sophistication incarnate!",
    g7sus4: "The suspended fourth! Delightfully unresolved, like a question mark in sonic form. We delay gratification by suspending the third with a fourth. It's musical foreplay, if you will.",
    pads: "Listen to those lush pads breathing in the stereo field! We're employing multiple oscillators with subtle detuning - what acousticians call chorus effect. It's like having an ensemble where everyone is slightly drunk, but in a good way.",
    drums: "The drums! Notice the micro-timing variations? That's J Dilla's gift to humanity - drunk drumming, scientifically known as quantization offset. Each hit deviates by milliseconds, creating what we call groove.",
    mastering: "Now for the mastering chain. We compress, we limit, we subtly distort. Think of it as audio cosmetic surgery - we're enhancing what nature gave us without looking too obvious about it.",
    loop: "And there we have it! The beat loops infinitely, like Sisyphus, but with significantly better rhythm section. Shall we continue our sonic education?"
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
