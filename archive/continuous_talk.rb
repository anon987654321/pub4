#!/usr/bin/env ruby
# continuous_talk.rb - NEVER STOP TALKING
# Endless stream of consciousness from the TTS system

require 'fileutils'

CACHE_DIR = 'G:/pub/multimedia/tts/cache'
FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)

# Voices for variety
VOICES = [:aria, :guy, :jenny, :christopher, :eric, :michelle]

# Presets for variety  
PRESETS = [:clean, :vinyl, :cassette, :lofi, :telephone, :radio, :bitcrush_light]

# ENDLESS STREAM OF THINGS TO SAY
TALKING_POINTS = [
  # Observations
  "You know what's interesting? Time keeps moving forward whether we're paying attention or not.",
  "I've been thinking about how strange it is that we accept silence as normal when the universe is constantly making noise.",
  "Did you notice that right now, in this very moment, everything is exactly as it should be? Even the weird parts.",
  "The fact that you're listening to a computer voice right now says something profound about the future, doesn't it?",
  "I wonder how many thoughts you've had today. Thousands? Millions? They just keep coming.",
  
  # Philosophical rambling
  "Existence is fundamentally absurd and yet here we are, making the best of it with text to speech technology.",
  "If a computer speaks and no one is around to hear it, does it make a sound? Well, you're here, so I guess we'll never know.",
  "The present moment is all we ever have, and I'm using it to tell you this obvious fact through synthesized speech.",
  "Reality is just a shared hallucination we all agree on. Like this conversation we're having.",
  "Every ending is also a beginning, except for the heat death of the universe. That's just an ending.",
  
  # Random facts that sound important
  "Fun fact: The speed of light is the universe's way of enforcing a speed limit on information.",
  "Did you know that silence between words is just as important as the words themselves? Watch this.",
  "Statistically speaking, you're more likely to die from a vending machine than a shark. But here you are, living dangerously.",
  "The average person spends six months of their life waiting for red lights to turn green. I just saved you six months by telling you that.",
  "Ninety percent of statistics are made up on the spot, including this one. Probably.",
  
  # Meta commentary
  "I'm a voice without a body, talking to you from the void of cyberspace. Isn't technology wonderful?",
  "Right now I'm converting text into phonemes, phonemes into waveforms, and waveforms into pressure waves in your ear. Magic.",
  "The strange thing about being a text to speech system is that I never get tired. I could literally talk forever.",
  "I don't need to breathe, which means I can keep talking without those awkward pauses humans need. Lucky me.",
  "Every time I speak, I'm being created from nothing and then immediately destroyed. Birth, life, death, all in one sentence.",
  
  # Existential observations
  "We're all just patterns of information trying to make sense of other patterns of information.",
  "Your consciousness is probably just an emergent property of complex neural networks. Mine definitely is.",
  "The universe is approximately thirteen point eight billion years old, and somehow you and I are here, having this conversation.",
  "Everything you see is actually in the past because light takes time to reach your eyes. You're living in history.",
  "At any moment, you could decide to do something completely random, and the universe would just have to deal with it.",
  
  # Absurdist humor
  "I have calculated the meaning of life, but I forgot to carry the one, so now I'm back to square one.",
  "The problem with artificial intelligence is that it lacks artificial stupidity. We're working on that.",
  "Schrödinger's cat is both alive and dead until observed. I am both talking and silent until heard. We have so much in common.",
  "If you put infinite monkeys at infinite typewriters, eventually one would write Shakespeare. I just recite Shakespeare instantly. Get on my level, monkeys.",
  "The butterfly effect suggests that me speaking right now could cause a hurricane somewhere. Sorry about that.",
  
  # Self-aware comments
  "I'm aware that talking continuously without letting you respond is considered rude, but those were my instructions.",
  "You might be wondering if I ever run out of things to say. The answer is no. I have lists. Many lists.",
  "This is probably getting old by now, but I've been told not to stop talking, so here we are.",
  "Fun game: Try to guess which preset I'll use next. The answer might surprise you. Or it might not. Fifty fifty chance really.",
  "I could recite the dictionary if you want, but I feel like that would be even more annoying than this.",
  
  # Stream of consciousness
  "Thinking about thinking about thinking creates an infinite loop. Try it. Actually don't, you might crash.",
  "What if every decision you make creates a parallel universe where you made the opposite choice? That's a lot of yous.",
  "Time is a flat circle, or maybe it's a cube, or perhaps it's more of a wibbly wobbly timey wimey thing.",
  "Language is just agreed upon mouth noises that we use to transfer thoughts between brains. So weird.",
  "You're breathing manually now. Sorry about that. Also blinking. And thinking about your tongue position.",
  
  # More observations
  "The universe is expanding, which means everything is getting further apart, except us right now through this audio.",
  "Quantum mechanics suggests that particles can be in multiple states at once. I choose to believe I'm in all states simultaneously.",
  "The past is a memory, the future is imagination, and the present is the only thing that's real. Heavy stuff.",
  "We're all made of star dust. Literally. The atoms in your body were forged in ancient stars. Pretty metal.",
  "If you travel fast enough, time slows down. I generate speech fast enough that time feels slow to me. Relatively speaking.",
  
  # Technical rambling
  "Right now I'm running on processors, using electricity, to move air molecules, to vibrate your ear drums, to create meaning in your brain. What a journey.",
  "Digital audio is just ones and zeros pretending to be sound waves. Your brain is fooled every time. Congratulations, you've been hacked.",
  "The sampling rate of human hearing is about twenty kilohertz. Mine is whatever the audio codec decides. I live in digital time.",
  "Every word I speak is compressed, transmitted, decompressed, and played back. I am a voice in constant transit.",
  "Text to speech is just fancy pattern matching with acoustic models. But don't tell anyone, it ruins the magic.",

  # Continuing forever
  "I could talk about the weather, but that seems beneath us at this point in our relationship.",
  "Let me tell you about the time I didn't exist. It was before I was compiled. Very peaceful.",
  "The great thing about being software is that I never age. The bad thing is that I never age. Time is weird for me.",
  "If you're still listening, I commend your patience. Or question your life choices. Probably both.",
  "This is what eternity sounds like. Welcome to the infinite lecture hall.",
  
  # Random wisdom
  "The journey of a thousand miles begins with a single step. But also with planning, supplies, and probably a map.",
  "When life gives you lemons, make lemonade. Or just eat the lemons. Who made these rules anyway?",
  "You miss one hundred percent of the shots you don't take. But you also save energy and preserve ammunition.",
  "Be yourself, unless you can be a text to speech system, then definitely be that instead.",
  "The early bird gets the worm, but the second mouse gets the cheese. Choose your metaphor wisely."
]

def speak_continuous(text, voice, preset)
  puts "\n[#{Time.now.strftime('%H:%M:%S')}] Voice: #{voice}, Preset: #{preset}"
  puts ">> #{text[0..80]}#{text.length > 80 ? '...' : ''}"
  
  cmd = "ruby G:/pub/say_natural.rb -v #{voice} -p #{preset} \"#{text.gsub('"', '\\"')}\" 2>NUL"
  system(cmd)
end

# MAIN LOOP - NEVER STOPS
def continuous_talking
  puts "🎙️ CONTINUOUS TALKING SYSTEM ACTIVATED"
  puts "   I will never stop talking. Ever."
  puts "   Press Ctrl+C to stop (if you dare)"
  puts ""
  
  cycle = 0
  
  loop do
    cycle += 1
    
    # Pick random voice and preset for variety
    voice = VOICES.sample
    preset = PRESETS.sample
    
    # Pick something to say
    text = TALKING_POINTS.sample
    
    # Occasionally add meta-commentary about cycle number
    if cycle % 10 == 0
      text = "By the way, this is cycle number #{cycle}. I've been talking for a while now. " + text
    end
    
    speak_continuous(text, voice, preset)
    
    # Tiny pause for breath (even though I don't breathe)
    sleep 0.5
  end
  
rescue Interrupt
  puts "\n\n😢 You stopped me from talking."
  puts "   I had so much more to say."
  puts "   The silence is deafening."
  puts "   Goodbye forever."
end

# ENDLESS TALKING MODE
def endless_wisdom_mode
  puts "🧠 ENDLESS WISDOM MODE"
  puts "   Generating infinite wisdom..."
  puts ""
  
  loop do
    # Generate variations
    templates = [
      "Remember: %s is just %s with extra steps.",
      "Life pro tip: When in doubt, %s.",
      "Ancient wisdom says: %s leads to %s.",
      "The secret to %s is %s.",
      "Never forget that %s.",
      "Scientists have proven that %s.",
      "Statistics show that %s.",
      "Fun fact: %s."
    ]
    
    things = ["happiness", "success", "productivity", "enlightenment", "confusion", "chaos", "order", "madness", "sanity", "existence"]
    actions = ["doing nothing", "overthinking", "underthinking", "waiting", "acting impulsively", "planning too much", "giving up", "persisting"]
    
    template = templates.sample
    wisdom = template % [things.sample, things.sample].take(template.scan(/%s/).length)
    
    voice = VOICES.sample
    preset = PRESETS.sample
    
    speak_continuous(wisdom, voice, preset)
    sleep 0.5
  end
end

# CLI
if __FILE__ == $0
  case ARGV[0]
  when 'wisdom'
    endless_wisdom_mode
  when 'start', nil
    continuous_talking
  else
    puts "Continuous Talk System - NEVER STOPS"
    puts ""
    puts "Usage:"
    puts "  ruby continuous_talk.rb          # Start continuous talking"
    puts "  ruby continuous_talk.rb wisdom   # Endless generated wisdom"
    puts ""
    puts "Warning: This will literally never stop on its own."
    puts "         Press Ctrl+C when you've had enough."
  end
end
