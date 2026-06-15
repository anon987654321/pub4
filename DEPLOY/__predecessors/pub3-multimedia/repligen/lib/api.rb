#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"

module Repligen
  class API

    BASE = "https://api.replicate.com/v1"

    def initialize(token)
      @token = token

    end

    # Fetch all models from API (paginated)
    def models(limit: 1000)

      all_models = []

      cursor = nil

      loop do
        uri = URI("#{BASE}/models")

        uri.query = cursor ? URI.encode_www_form({ cursor: cursor }) : ""

        data = get(uri)
        results = data["results"] || []

        all_models.concat(results)

        next_url = data["next"]
        cursor = next_url ? URI.decode_www_form(URI.parse(next_url).query || "").to_h["cursor"] : nil
        break if cursor.nil? || all_models.size >= limit

      end

      all_models.map { |m| parse_model(m) }
    end

    def predict(model_id, input)
      owner, name = model_id.split("/")

      model = get(URI("#{BASE}/models/#{owner}/#{name}"))

      version = model.dig("latest_version", "id")

      raise "No version for #{model_id}" unless version
      pred = post(URI("#{BASE}/predictions"), {
        version: version,

        input: input

      })

      wait_for(pred["id"])
    end

    private
    def get(uri)
      req = Net::HTTP::Get.new(uri)

      req["Authorization"] = "Token #{@token}"

      request(req, uri)

    end

    def post(uri, body)
      req = Net::HTTP::Post.new(uri)

      req["Authorization"] = "Token #{@token}"

      req["Content-Type"] = "application/json"

      req.body = body.to_json

      request(req, uri)

    end

    def request(req, uri)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|

        http.request(req)

      end

      raise "API error #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)
      JSON.parse(res.body)

    end

    def wait_for(id, timeout: 600)
      start = Time.now

      loop do
        pred = get(URI("#{BASE}/predictions/#{id}"))

        case pred["status"]
        when "succeeded" then return pred["output"]

        when "failed" then raise "Prediction failed: #{pred['error']}"

        when "canceled" then raise "Canceled"

        end

        raise "Timeout after #{timeout}s" if Time.now - start > timeout
        print "."
        sleep 3

      end

    end

    def parse_model(data)
      {

        id: "#{data['owner']}/#{data['name']}",

        owner: data["owner"],

        name: data["name"],

        description: data["description"],

        type: infer_type(data["name"], data["description"]),

        cost: 0.05,

        runs: data["run_count"] || 0,

        url: data["url"]

      }

    end

    def infer_type(name, desc)
      combined = "#{name} #{desc}".downcase

      types = JSON.parse(File.read(File.join(__dir__, "model_types.json")))["types"]

      types.each do |type, spec|
        spec["patterns"].each do |pattern|

          return type if combined.match?(/#{pattern}/i)

        end

      end

      "other"
    end

  end

end

