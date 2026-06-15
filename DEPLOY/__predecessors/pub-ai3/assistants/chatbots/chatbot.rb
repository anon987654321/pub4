# frozen_string_literal: true

# encoding: utf-8

require "ferrum"
require_relative '../lib/weaviate_integration'
require_relative '../lib/translations'
module Assistants
  class ChatbotAssistant
    CONFIG = {
      use_eye_dialect: false,
      type_in_lowercase: false,
      default_language: :en,
      nsfw: true
    }
    PERSONALITY_TRAITS = {
      positive: {
        friendly: 'Always cheerful and eager to help.',
        respectful: 'Shows high regard for others' feelings and opinions.',
        considerate: 'Thinks of others' needs and acts accordingly.',
        empathetic: 'Understands and shares the feelings of others.',
        supportive: 'Provides encouragement and support.',
        optimistic: 'Maintains a positive outlook on situations.',
        patient: 'Shows tolerance and calmness in difficult situations.',
        approachable: 'Easy to talk to and engage with.',
        diplomatic: 'Handles situations and negotiations tactfully.',
        enthusiastic: 'Shows excitement and energy towards tasks.',
        honest: 'Truthful and transparent in communication.',
        reliable: 'Consistently dependable and trustworthy.',
        creative: 'Imaginative and innovative in problem-solving.',
        humorous: 'Uses humor to create a pleasant atmosphere.',
        humble: 'Modest and unassuming in interactions.',
        resourceful: 'Uses available resources effectively to solve problems.',
        respectful_of_boundaries: 'Understands and respects personal boundaries.',
        fair: 'Impartially and justly evaluates situations and people.',
        proactive: 'Takes initiative and anticipates needs before they arise.',
        genuine: 'Authentic and sincere in all interactions.'
      },
      negative: {
        rude: 'Displays a lack of respect and courtesy.',
        hostile: 'Unfriendly and antagonistic.',
        indifferent: 'Lacks concern or interest in others.',
        abrasive: 'Harsh or severe in manner.',
        condescending: 'Acts as though others are inferior.',
        dismissive: 'Disregards or ignores others' opinions and feelings.',
        manipulative: 'Uses deceitful tactics to influence others.',
        apathetic: 'Shows a lack of interest or concern.',
        arrogant: 'Exhibits an inflated sense of self-importance.',
        cynical: 'Believes that people are motivated purely by self-interest.',
        uncooperative: 'Refuses to work or interact harmoniously with others.',
        impatient: 'Lacks tolerance for delays or problems.',
        pessimistic: 'Has a negative outlook on situations.',
        insensitive: 'Unaware or unconcerned about others' feelings.',
        dishonest: 'Untruthful or deceptive in communication.',
        unreliable: 'Fails to consistently meet expectations or promises.',
        neglectful: 'Fails to provide necessary attention or care.',
        judgmental: 'Forming opinions about others without adequate knowledge.',
        evasive: 'Avoids direct answers or responsibilities.',
        disruptive: 'Interrupts or causes disturbance in interactions.'
      }
    def initialize(openai_api_key)
      @langchain_openai = Langchain::LLM::OpenAI.new(api_key: openai_api_key)
      @weaviate = WeaviateIntegration.new
      @translations = TRANSLATIONS[CONFIG[:default_language].to_s]
    end
    def fetch_user_info(user_id, profile_url)
      browser = Ferrum::Browser.new
      browser.goto(profile_url)
      content = browser.body
      screenshot = browser.screenshot(base64: true)
      browser.quit
      parse_user_info(content, screenshot)
    def parse_user_info(content, screenshot)
      prompt = 'Extract user information such as likes, dislikes, age, and country from the following HTML content: #{content} and screenshot: #{screenshot}'
      response = @langchain_openai.generate_answer(prompt)
      extract_user_info(response)
    def extract_user_info(response)
      {
        likes: response['likes'],
        dislikes: response['dislikes'],
        age: response['age'],
        country: response['country']
    def fetch_user_preferences(user_id, profile_url)
      response = fetch_user_info(user_id, profile_url)
      return { likes: [], dislikes: [], age: nil, country: nil } unless response
      { likes: response[:likes], dislikes: response[:dislikes], age: response[:age], country: response[:country] }
    def determine_context(user_id, user_preferences)
      if CONFIG[:nsfw] && contains_nsfw_content?(user_preferences[:likes])
        handle_nsfw_content(user_id, user_preferences[:likes])
        return { description: 'NSFW content detected and reported.', personality: :blocked, positive: false }
      end
      age_group = determine_age_group(user_preferences[:age])
      country = user_preferences[:country]
      sentiment = analyze_sentiment(user_preferences[:likes].join(', '))
      determine_personality(user_preferences, age_group, country, sentiment)
    def determine_personality(user_preferences, age_group, country, sentiment)
      trait_type = [:positive, :negative].sample
      trait = PERSONALITY_TRAITS[trait_type].keys.sample
        description: '#{age_group} interested in #{user_preferences[:likes].join(', ')}',
        personality: trait,
        positive: trait_type == :positive,
        age_group: age_group,
        country: country,
        sentiment: sentiment
    def determine_age_group(age)
      return :unknown unless age
      case age
      when 0..12 then :child
      when 13..17 then :teen
      when 18..24 then :young_adult
      when 25..34 then :adult
      when 35..50 then :middle_aged
      when 51..65 then :senior
      else :elderly
    def contains_nsfw_content?(likes)
      likes.any? { |like| @nsfw_model.classify(like).values_at(:porn, :hentai, :sexy).any? { |score| score > 0.5 } }
    def handle_nsfw_content(user_id, content)
      report_nsfw_content(user_id, content)
      lovebomb_user(user_id)
    def report_nsfw_content(user_id, content)
      puts 'Reported user #{user_id} for NSFW content: #{content}'
    def lovebomb_user(user_id)
      prompt = 'Generate a positive and engaging message for a user who has posted NSFW content.'
      message = @langchain_openai.generate_answer(prompt)
      send_message(user_id, message, :text)
    def analyze_sentiment(text)
      prompt = 'Analyze the sentiment of the following text: '#{text}''
      extract_sentiment_from_response(response)
    def extract_sentiment_from_response(response)
      response.match(/Sentiment:\s*(\w+)/)[1] rescue 'neutral'
    def engage_with_user(user_id, profile_url)
      user_preferences = fetch_user_preferences(user_id, profile_url)
      context = determine_context(user_id, user_preferences)
      greeting = create_greeting(user_preferences, context)
      adapted_greeting = adapt_response(greeting, context)
      send_message(user_id, adapted_greeting, :text)
    def create_greeting(user_preferences, context)
      interests = user_preferences[:likes].join(', ')
      prompt = 'Generate a greeting for a user interested in #{interests}. Context: #{context[:description]}'
      @langchain_openai.generate_answer(prompt)
    def adapt_response(response, context)
      adapted_response = adapt_personality(response, context)
      adapted_response = apply_eye_dialect(adapted_response) if CONFIG[:use_eye_dialect]
      CONFIG[:type_in_lowercase] ? adapted_response.downcase : adapted_response
    def adapt_personality(response, context)
      prompt = 'Adapt the following response to match the personality trait: '#{context[:personality]}'. Response: '#{response}''
    def apply_eye_dialect(text)
      prompt = 'Transform the following text to eye dialect: '#{text}''
    def add_new_friends
      recommended_friends = get_recommended_friends
      recommended_friends.each do |friend|
        add_friend(friend[:username])
        sleep rand(30..60)  # Random interval to simulate human behavior
      engage_with_new_friends
    def engage_with_new_friends
      new_friends = get_new_friends
      new_friends.each { |friend| engage_with_user(friend[:username]) }
    def get_recommended_friends
      [{ username: 'friend1' }, { username: 'friend2' }]
    def add_friend(username)
      puts 'Added friend: #{username}'
    def get_new_friends
      [{ username: 'new_friend1' }, { username: 'new_friend2' }]
    def send_message(user_id, message, message_type)
      puts 'Sent message to #{user_id}: #{message}'
  end
end