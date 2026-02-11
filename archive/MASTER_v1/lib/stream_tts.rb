# frozen_string_literal: true

module MASTER
  # StreamTTS: Real-time TTS streaming with live audio effects
  # Uses IO.popen for elegant Unix-style pipe handling
  module StreamTTS
    extend self

    # Voice settings
    VOICE = 'en-US-GuyNeural'
    RATE_DARK = '-25%'
    PITCH_DARK = '-25Hz'
    RATE_DEMON = '-35%'
    PITCH_DEMON = '-35Hz'

    # FFmpeg paths (adjust for platform)
    FFMPEG = ENV['FFMPEG_PATH'] || 'ffmpeg'
    FFPLAY = ENV['FFPLAY_PATH'] || 'ffplay'

    # Effect presets
    EFFECTS = {
      dark: 'asetrate=44100*0.8,atempo=1.25,bass=g=10',
      demon: 'asetrate=44100*0.7,atempo=1.4,bass=g=15,acompressor=threshold=0.08:ratio=12',
      robot: 'asetrate=44100*0.9,atempo=1.1,flanger,tremolo=f=10:d=0.5',
      radio: 'highpass=f=300,lowpass=f=3000,acompressor=threshold=0.1:ratio=8',
      underwater: 'asetrate=44100*0.6,atempo=1.6,lowpass=f=800,chorus=0.5:0.9:50:0.4:0.25:2',
      ghost: 'asetrate=44100*0.75,atempo=1.33,areverse,aecho=0.8:0.88:60:0.4,areverse'
    }.freeze

    # Stream TTS directly to speakers with effects
    def stream(text, effect: :dark, voice: VOICE, rate: RATE_DARK, pitch: PITCH_DARK)
      tts_cmd = ['python', '-m', 'edge_tts',
                 '--text', text,
                 '--voice', voice,
                 "--rate=#{rate}",
                 "--pitch=#{pitch}",
                 '--write-media', '-']

      fx_filter = EFFECTS[effect] || EFFECTS[:dark]

      tts = IO.popen(tts_cmd, 'rb', err: File::NULL)
      fx = IO.popen([FFMPEG, '-i', 'pipe:0', '-af', fx_filter, '-f', 'wav', 'pipe:1'],
                    'r+b', err: File::NULL)
      play = IO.popen([FFPLAY, '-nodisp', '-autoexit', '-i', 'pipe:0'],
                      'wb', err: File::NULL)

      # Async pipe: TTS -> Effects
      Thread.new { IO.copy_stream(tts, fx); fx.close_write }
      
      # Effects -> Speakers
      IO.copy_stream(fx, play)

      [tts, fx, play].each(&:close)
    rescue => e
      warn "StreamTTS error: #{e.message}"
    end

    # Stream without effects (raw TTS)
    def stream_raw(text, voice: VOICE, rate: RATE_DARK, pitch: PITCH_DARK)
      tts_cmd = ['python', '-m', 'edge_tts',
                 '--text', text,
                 '--voice', voice,
                 "--rate=#{rate}",
                 "--pitch=#{pitch}",
                 '--write-media', '-']

      tts = IO.popen(tts_cmd, 'rb', err: File::NULL)
      play = IO.popen([FFPLAY, '-nodisp', '-autoexit', '-i', 'pipe:0'],
                      'wb', err: File::NULL)

      IO.copy_stream(tts, play)
      [tts, play].each(&:close)
    rescue => e
      warn "StreamTTS error: #{e.message}"
    end

    # Demon mode: maximum darkness
    def demon(text)
      stream(text, effect: :demon, rate: RATE_DEMON, pitch: PITCH_DEMON)
    end

    # Continuous loop: never stops talking
    def loop_forever(texts, effect: :dark, delay: 0.5)
      texts = [texts] if texts.is_a?(String)
      loop do
        stream(texts.sample, effect: effect)
        sleep delay
      end
    end

    # Adversarial loop: challenging questions
    def adversarial_loop(iterations: 5)
      challenges = [
        'Why are you still using external processes when Ruby can do it all?',
        'Have you considered that your entire approach might be wrong?',
        'What if everything you know about shell scripting is outdated?',
        'Are you afraid to push the boundaries of what code can be?',
        'Why do you accept mediocrity when excellence is within reach?',
        'When was the last time you deleted code instead of adding more?',
        'Is your code beautiful or just functional?'
      ]

      commands = %w[FIX\ IT DO\ BETTER TRY\ AGAIN PROVE\ IT DELETE\ IT REWRITE\ IT]

      iterations.times do |i|
        text = "#{challenges.sample}... #{commands.sample}... Iteration #{i + 1}."
        demon(text)
        sleep 0.3
      end
    end

    # MASTER description recitation
    def recite_master
      sections = [
        'MASTER is the beating heart. A pure Ruby LLM Operating System.',
        'Constitutional AI with 43 principles. KISS. DRY. OpenBSD pledge.',
        'Nine orb animations. Retro 4-bit. Particle effects. 3D sphere.',
        'Self improvement loop. Optimize. Refactor. Evolve. Introspect.',
        'Less than 10 thousand lines. Constitutional AI. OpenBSD hardening.'
      ]

      sections.each { |s| demon(s); sleep 0.2 }
    end
  end
end
