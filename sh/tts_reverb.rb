#!/usr/bin/env ruby
# Real-time TTS with offline reverb processing

require 'win32ole'
require 'fileutils'

class TTSReverb
  def initialize
    @speech = WIN32OLE.new('SAPI.SpVoice')
    @tmpdir = 'G:/pub'
    @sox = 'C:/cygwin64/bin/sox.exe'
  end
  
  def speak_realtime(text, rate: 0, volume: 100)
    @speech.Rate = rate
    @speech.Volume = volume
    @speech.Speak(text, 1)
  end
  
  def speak_reverb(text, rate: -3, reverb: 'cave')
    wav = "#{@tmpdir}/tts_#{Time.now.to_i}.wav"
    out = "#{@tmpdir}/tts_reverb_#{Time.now.to_i}.wav"
    
    @speech.Rate = rate
    @speech.Volume = 100
    @speech.SetOutputToWaveFile(wav)
    @speech.Speak(text)
    @speech.SetOutputToDefaultAudioDevice()
    
    effects = case reverb
    when 'cave' then 'reverb 100 50 100 100 0 0'
    when 'echo' then 'echo 0.8 0.9 60 0.3'
    when 'cathedral' then 'reverb 80 100 100 100 0 10'
    when 'underwater' then 'pitch -200 phaser 0.6 0.66 3 0.6 0.5'
    else 'reverb 50 50 100 100 0 0'
    end
    
    system("#{@sox} #{wav} #{out} #{effects} 2>nul")
    system("powershell.exe -Command \"(New-Object Media.SoundPlayer '#{out}').PlaySync()\" 2>nul")
    
    File.delete(wav) rescue nil
    File.delete(out) rescue nil
  end
end

tts = TTSReverb.new

ARGV.empty? ? tts.speak_realtime("T T S Reverb system activated") : 
              tts.send(ARGV[0].to_sym, *ARGV[1..-1])
