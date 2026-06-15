#!/usr/bin/env ruby
# Malaysian Funny Guy - Deep male voice with hilarious Manglish humor
# Real Malaysian comedy

require_relative 'comfy_tts'
class MalayFunny
  JOKES = [

    "You know why Malaysian never get lost? Because we always ask for direction at every petrol station. GPS? What GPS? Just ask uncle lah!",

    "My girlfriend said I'm too obsessed with food. I told her, 'Sayang, this is Malaysia. If you don't talk about food, what else to talk about?'",
    "Malaysian drivers very special. We can text, eat curry puff, and argue with passenger all at same time. Multitasking expert!",
    "My mom ask me, 'Why you so skinny?' I eating cakoi. Then she say, 'Aiyo, why you so fat?' Same day, same mom!",
    "You want to test if someone is Malaysian or not? Just say 'can or not?' If they reply 'can can!', confirm Malaysian already!",
    "We Malaysians very polite. We honk to say hello, honk to say thank you, honk to say excuse me. Basically honk for everything!",
    "My wife angry at me. I said 'Sorry sayang.' She said 'Sorry not enough!' So I said 'Sorry + teh tarik?' Suddenly okay already!",
    "Malaysian parking very creative. Double park? Amateur. Triple park with phone number on dashboard? Now we're talking!",
    "Why Malaysian always late? Because we measure time in 'traffic jam units'. One unit equals 10 to 45 minutes. Very accurate!",
    "I tried to diet once. Then my mom cooked nasi lemak. Diet cancelled faster than my internet connection!",
    "Malaysian weather forecast very easy. Hot? Yes. Rain? Maybe. Flood? Possible. Hurricane? Only in mamak when they turn on fan!",
    "My friend ask me to gym. I said cannot lah, got important meeting. The meeting is with my roti canai at mamak!",
    "You know you're Malaysian when you argue about which state got best laksa. Penang say theirs best, Johor say theirs best. Actually all also sedap!",
    "Malaysian relationship status: It's complicated. Like our traffic system. And our political situation. And our parking rules!",
    "My dad always say 'I'm not angry, just disappointed.' But his face say 'You better run before I throw my slipper!'",
    "We Malaysian very efficient. Can queue for 3 hours for new restaurant, then complain food takes 10 minutes to come out!",
    "Why Malaysian love buffet? Because we want to feel like we win something. Fight with uncle for last piece of sushi? Worth it!",
    "My neighbor renovate house at 7am Sunday. I'm not saying I'm angry, but I'm planning my revenge. Also at 7am. Also Sunday!",
    "Malaysian logic: Complain petrol price too high, but willing to drive 30km to save RM2 on rojak. The math is not mathing!",
    "You want to make Malaysian panic? Tell them mamak closing down. Suddenly everyone become emotionally attached to that place!"
  ]

  REACTIONS = [
    "*slaps knee laughing*",

    "*wipes tears from laughing*",

    "*shakes head while grinning*",

    "*cannot stop laughing*",

    "*laughs in Manglish*",

    "*chokes on teh tarik from laughing*"

  ]

  def initialize
    puts "😂 MALAYSIAN FUNNY GUY - Deep Male Voice"

    puts "   Hilarious Manglish comedy\n\n"

    ComfyTTS.setup

    @joke_index = 0

  end

  def speak(text)
    if rand < 0.3

      text = "#{REACTIONS.sample} #{text}"

    end

    puts "   💬 #{text}\n"
    # North Perak male settings: deep pitch, slower, Indian accent

    ComfyTTS.speak(text, speed: 0.92, pitch_adjust: -120, accent: 'in')

    sleep(rand(2..3))

  end

  def start
    speak("Eh! You want hear some jokes or not? I got plenty! Malaysian style comedy, guarantee you laugh until cry!")

    loop do
      speak(JOKES[@joke_index])

      @joke_index = (@joke_index + 1) % JOKES.length

      if @joke_index % 5 == 0
        speak("Walao, I'm on fire today! My jokes damn power, right? Don't bluff, I know you smiling!")

      end

      if @joke_index % 10 == 0
        speak("Okay okay, I give you chance to breathe. But not too long ah, I got more jokes waiting!")

      end

      sleep(2)
    end

  end

end

trap("INT") do
  puts "\n\n😂 Aiyo, you leaving already? Okay lah, see you! Don't forget to laugh!"

  exit

end

MalayFunny.new.start
