#!/usr/bin/env ruby
# idle_advice.rb - Stupid life advice from the strange voice
# Lame, weird, awkward self-help when idle

require 'fileutils'

CACHE_DIR = 'G:/pub/multimedia/tts/strange_cache'
FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)

# Stupid and lame life advice
ADVICE = [
  "Have you tried turning yourself off and on again?",
  "Remember: If you can't solve a problem, just ignore it until it becomes someone else's problem",
  "Life pro tip: Wear sunglasses indoors so people think you're mysterious instead of just avoiding eye contact",
  "The secret to happiness is low expectations and high caffeine intake",
  "If you're feeling unproductive, remember: doing nothing is actually practicing mindfulness",
  "Stop comparing yourself to others. Compare yourself to who you were yesterday. Then feel bad about that too",
  "Success tip: Just keep refreshing your email until opportunities appear",
  "Self-care reminder: It's okay to take a break from taking breaks",
  "Motivational quote: You miss one hundred percent of the naps you don't take",
  "Productivity hack: Make a to-do list, then lose it, then make another one",
  "Life advice: When in doubt, restart your computer. And your life. But mostly your computer",
  "Remember: Everyone you meet is fighting a battle you know nothing about. So just avoid everyone",
  "The key to success is persistence. Or maybe it's giving up at the right time. Hard to tell",
  "Self-improvement tip: Start a journal, write in it once, then feel guilty about it for six months",
  "Social skills advice: If you can't think of anything to say, just describe the weather in great detail",
  "Career advice: Follow your passion, unless your passion is unprofitable, then get a real job",
  "Mental health tip: Overthinking is just planning for scenarios that will never happen",
  "Relationship advice: Communication is key. But also, saying nothing works sometimes",
  "Exercise motivation: Your body is a temple. A temple full of snacks and regret",
  "Financial wisdom: Save money by not buying things. Except coffee. Always buy coffee",
  "Time management: Procrastinate now, panic later. It's called planning",
  "Healthy eating tip: Pizza is a vegetable if you believe hard enough",
  "Sleep advice: Go to bed early so you can lie awake thinking about all your life choices",
  "Stress management: Just remember, in a hundred years, everyone you know will be dead anyway",
  "Confidence tip: Fake it till you make it. Then keep faking it because what if they find out",
  "Work-life balance: Work eight hours, sleep eight hours. Just make sure they're not the same eight hours",
  "Spiritual wisdom: Find your inner peace. It's probably behind the couch with your missing socks",
  "Learning tip: You can learn anything on YouTube at 2x speed. Understanding it is optional",
  "Decluttering advice: Throw everything away. You probably won't need it. Until you do",
  "Mindfulness practice: Be present in the moment. Especially the awkward ones",
  "Networking tip: Make eye contact, smile, then immediately forget their name",
  "Goal setting: Aim for the stars. Miss. End up in the cold vacuum of space. Realistic",
  "Creativity hack: Writer's block is just your brain's way of saying take a three-hour nap",
  "Emotional intelligence: Feelings are like code errors. Just ignore them and hope they go away",
  "Personal growth: Every mistake is a learning opportunity. You must be very educated by now",
  "Hydration reminder: Drink eight glasses of water a day, or just drink coffee. Coffee is mostly water",
  "Posture check: Stop slouching. Actually, you know what, just embrace it. You're a gargoyle now",
  "Breathing exercise: Inhale. Exhale. Repeat. Congratulations, you're still alive",
  "Digital detox: Delete all your apps. Reinstall them five minutes later. Feel accomplished",
  "Self-reflection: Look in the mirror and ask yourself the hard questions. Then avoid answering them",
  "Life philosophy: Everything happens for a reason. The reason is usually poor decision making",
  "Wisdom from the void: Success is ten percent inspiration and ninety percent pretending you know what you're doing",
  "Ancient proverb: A journey of a thousand miles begins with a single step. Then complaining about your feet",
  "Deep thought: If a tree falls in the forest and no one hears it, it's probably because they're all on their phones",
  "Enlightenment: The meaning of life is... buffering... please wait... connection timed out",
  "Zen koan: What is the sound of one hand clapping? It's probably arthritis",
  "Daily affirmation: I am enough. I am worthy. I am questioning why I'm talking to myself",
  "Morning routine: Wake up. Regret. Coffee. More regret. That's the circle of life",
  "Evening ritual: Reflect on your day. Cringe at everything you said. Plan to be better tomorrow. Repeat",
  "Life strategy: Hope for the best, expect the worst, settle for mediocrity"
]

# More awkward advice
AWKWARD_TIPS = [
  "Conversation starter: Tell people about your dreams. In vivid detail. Don't stop until they leave",
  "Icebreaker: Ask someone how they're doing, then share your entire medical history",
  "Small talk tip: When someone says 'how are you', respond with 'let me tell you' and never stop",
  "Party trick: Stand in the corner and make everyone uncomfortable with intense eye contact",
  "Networking: Collect business cards you'll never look at again. It's called professional development",
  "Public speaking: Just imagine everyone in their underwear. Now you're even more nervous",
  "Job interview: When they ask about weaknesses, list them all. Honesty is the best policy",
  "First date: Talk exclusively about your ex. Show pictures. Compare your dates. Perfect",
  "Making friends: Follow people home. Wait, no, that's stalking. Just send weird memes instead",
  "Conflict resolution: Passive-aggressive silence followed by oversharing. Classic"
]

# Text corruption for advice
def corrupt_text(text)
  words = text.split(' ')
  glitches = ['*bzzt*', '*crackle*', '*static*']
  
  result = []
  words.each do |word|
    result << glitches.sample if rand < 0.2  # Less corruption for readability
    
    if rand < 0.2 && word.length > 3
      first = word[0]
      result << "#{first}-#{first}-#{word}"
    else
      result << word
    end
    
    result << word if rand < 0.15
  end
  
  result.join(' ')
end

# Random voice
def random_advice_voice
  [
    { voice: 'en+m3', pitch: 30, speed: 120 },    # Slightly deep, slow
    { voice: 'en+f2', pitch: 50, speed: 140 },    # Female, normal
    { voice: 'en+croak', pitch: 20, speed: 100 }, # Croaky wise man
    { voice: 'en+whisper', pitch: 60, speed: 110 } # Conspiratorial whisper
  ].sample
end

# Speak advice
def speak_advice(text)
  corrupted = corrupt_text(text)
  puts "\n💡 [ADVICE] #{corrupted}\n"
  
  voice = random_advice_voice
  temp_wav = "#{CACHE_DIR}/advice_#{Time.now.to_i}.wav"
  cygwin_path = "/cygdrive/g/pub/multimedia/tts/strange_cache/advice_#{Time.now.to_i}.wav"
  
  cmd = "espeak -v #{voice[:voice]} -p #{voice[:pitch]} -s #{voice[:speed]} -w #{cygwin_path} \"#{corrupted.gsub('"', '\\"')}\" 2>/dev/null"
  system("C:/cygwin64/bin/bash.exe", "-l", "-c", cmd)
  
  if File.exist?(temp_wav)
    ps = <<~PS
      Add-Type -AssemblyName System.Windows.Forms
      $player = New-Object System.Media.SoundPlayer('#{temp_wav.gsub('/', '\\')}')
      $player.PlaySync()
    PS
    
    system("powershell.exe", "-Command", ps)
    File.delete(temp_wav) if File.exist?(temp_wav)
  end
end

# Main idle loop
def idle_advice_loop(interval_minutes: 5)
  puts "🧘 Idle Advice System Started"
  puts "   Interval: #{interval_minutes} minutes"
  puts "   Press Ctrl+C to stop"
  puts ""
  
  loop do
    sleep(interval_minutes * 60)
    
    advice_pool = ADVICE + AWKWARD_TIPS
    advice = advice_pool.sample
    
    speak_advice(advice)
  end
rescue Interrupt
  puts "\n\n👋 Advice system stopped. Remember: giving up is also a valid life strategy!"
end

# CLI
if __FILE__ == $0
  case ARGV[0]
  when 'start'
    interval = (ARGV[1] || 5).to_i
    idle_advice_loop(interval_minutes: interval)
  
  when 'once'
    advice = (ADVICE + AWKWARD_TIPS).sample
    speak_advice(advice)
  
  when 'list'
    puts "Available advice (#{ADVICE.length + AWKWARD_TIPS.length} total):"
    (ADVICE + AWKWARD_TIPS).each_with_index do |advice, i|
      puts "#{i+1}. #{advice}"
    end
  
  else
    puts "Idle Advice System - Stupid Life Advice from Strange Voice"
    puts ""
    puts "Usage:"
    puts "  ruby idle_advice.rb start [minutes]   - Start idle loop (default: 5 min)"
    puts "  ruby idle_advice.rb once               - Say one piece of advice now"
    puts "  ruby idle_advice.rb list               - List all advice"
    puts ""
    puts "Examples:"
    puts "  ruby idle_advice.rb start 5    # Advice every 5 minutes"
    puts "  ruby idle_advice.rb start 1    # Advice every minute (annoying)"
    puts "  ruby idle_advice.rb once       # One random advice"
  end
end
