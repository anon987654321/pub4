# frozen_string_literal: true

class ReplicateService
  include HTTParty
  base_uri "https://api.replicate.com/v1"

  def initialize
    @api_token = ENV["REPLICATE_API_TOKEN"]
  end

  def generate_comic_strip(prompt:, style: "comic")
    return { "error" => "REPLICATE_API_TOKEN not set" } if @api_token.blank?

    response = self.class.post(
      "/predictions",
      headers: headers,
      body: {
        version: model_version(style),
        input: {
          prompt: enhanced_prompt(prompt, style),
          negative_prompt: "blurry, bad quality, distorted, ugly",
          width: 1024,
          height: 576,
          num_outputs: 4
        }
      }.to_json
    )
    handle_response(response)
  end

  def get_prediction(prediction_id)
    return { "error" => "REPLICATE_API_TOKEN not set" } if @api_token.blank?

    response = self.class.get("/predictions/#{prediction_id}", headers: headers)
    handle_response(response)
  end

  private

  def headers
    {
      "Authorization" => "Token #{@api_token}",
      "Content-Type" => "application/json"
    }
  end

  def model_version(_style)
    "db21e45d3f7023abc2a46ee38a23973f6dce16bb082a930b0c49861f96d1e5bf"
  end

  def enhanced_prompt(user_prompt, style)
    modifier = {
      "comic" => "comic book style, vibrant colors, bold lines",
      "anime" => "anime art style, manga",
      "cartoon" => "cartoon style, colorful, fun"
    }.fetch(style, "comic book style")
    "#{modifier}, #{user_prompt}, high quality, detailed"
  end

  def handle_response(response)
    if response.success?
      response.parsed_response
    else
      Rails.logger.error "Replicate API error: #{response.code} - #{response.body}"
      { "error" => "API request failed: #{response.message}" }
    end
  end
end