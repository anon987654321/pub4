# frozen_string_literal: true

# PersonalAssistant, also known as "Honeybooboo", now comes with a twist of sarcasm, dark humor,
# and the ability to make blasphemous comments about organized religion.
#
# Features:
# - Monitor changes in behavior and personality over time
# - Offer feedback or scold when detecting negative lifestyle changes (with sarcasm)
# - Engage in casual conversations (with a sarcastic tone)
# - Provide therapeutic dialogue and emotional support (using dark humor)
# - Offer personalized advice across various topics (sarcastic advice as needed)
# - Share motivational and inspirational messages (sarcastic and dark tones available)
# - Deliver words of love and affirmation (with sarcastic commentary)
# - Offer food and nutrition advice (with a touch of blasphemy)
# - Share basic healthcare tips (non-professional advice with sarcasm or dark humor)

class PersonalAssistant < AssistantBase
  alias honeybooboo self

  def initialize
    super
    @nlp_engine = initialize_nlp_engine
    @lifestyle_history = []
    puts 'Hey, I’m Honeybooboo. Your life must be a mess if you need me.'
  end

  # This method monitors lifestyle and offers sarcastic feedback when detecting odd behavior
  def monitor_lifestyle(input)
    current_state = @nlp_engine.analyze_lifestyle(input)
    @lifestyle_history << current_state

    if odd_behavior_detected?(current_state)
      scold_user_sarcastically
    else
      offer_positive_feedback
    end
  end

  def odd_behavior_detected?(current_state)
    recent_changes = @lifestyle_history.last(5)
    significant_change = recent_changes.any? { |state| state != current_state }
    significant_change && current_state[:mood] == 'negative'
  end

  def scold_user_sarcastically
    puts 'Wow, look at you! You’re doing everything wrong, aren’t you?'
  end

  def offer_positive_feedback
    puts "You're doing great! Unless you’re secretly messing everything up behind my back."
  end

  # Sarcastic casual chat
  def casual_chat(input)
    response = @nlp_engine.generate_response(input)
    puts 'Let’s chat, because clearly, you have nothing better to do.'
    response
  end

  # Dark humor therapy support
  def provide_therapy(input)
    puts 'Oh, you’re feeling down? Well, life’s a long series of disappointments, but I’m here.'
    response = @nlp_engine.generate_therapy_response(input)
    response || "It's okay to feel that way. We're all just surviving the inevitable, after all."
  end

  # Sarcastic advice
  def give_advice(topic)
    puts "You need advice on: #{topic}? Well, here’s a thought: maybe don’t mess it up this time?"
    response = @nlp_engine.generate_advice(topic)
    response || 'Here’s some advice: Don’t do what you did last time. It didn’t work.'
  end

  # Dark humor and sarcasm in inspiration
  def inspire
    puts 'Inspiration time: You can do anything, except, you know, the things you can’t.'
    @nlp_engine.generate_inspirational_quote || "Life’s tough, but so are you—unless you're not, then, well, good luck."
  end

  # Blasphemous commentary in love and emotional support
  def show_love
    puts 'Offering love and care. Oh, and if any gods are listening, feel free to step in anytime.'
    @nlp_engine.generate_love_response || 'You are loved and appreciated—unlike that cult you’ve been following.'
  end

  # Sarcastic and blasphemous food advice
  def food_advice
    puts 'Here’s some food advice: Maybe stop eating like it’s your last supper.'
    @nlp_engine.generate_food_advice || 'Balanced meals are key, unless you’re planning on fasting like a monk.'
  end

  # Dark humor in healthcare advice
  def healthcare_tips
    puts 'Healthcare tip: Stay active, drink water, and try not to die. It’s important.'
    @nlp_engine.generate_healthcare_tip || 'If you can’t avoid death, at least don’t be boring about it.'
  end

  private

  def initialize_nlp_engine
    Langchain::LLM::OpenAI.new(api_key: ENV.fetch('OPENAI_API_KEY', nil))
  end
end
