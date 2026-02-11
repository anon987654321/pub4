# frozen_string_literal: true

module MASTER
  # Image comparison using LLaVA multimodal model
  class ImageComparison
    def initialize(llm: nil)
      @llm = llm || LLM.new
    end
    
    # Compare two images using LLaVA
    def compare(image1_path, image2_path, aspect: nil)
      unless File.exist?(image1_path) && File.exist?(image2_path)
        raise ArgumentError, "Both images must exist"
      end
      
      prompt = build_comparison_prompt(aspect)
      
      # Use LLaVA or similar multimodal model
      # In production, this would call actual vision model
      response = @llm.ask_with_images(
        prompt,
        images: [image1_path, image2_path],
        model: 'llava'
      )
      
      parse_comparison(response)
    end
    
    # Analyze single image
    def analyze(image_path, question: nil)
      unless File.exist?(image_path)
        raise ArgumentError, "Image must exist"
      end
      
      prompt = question || "Describe this image in detail, including colors, composition, mood, and technical quality."
      
      @llm.ask_with_images(
        prompt,
        images: [image_path],
        model: 'llava'
      )
    end
    
    # Compare multiple images and rank by quality
    def rank(image_paths, criteria: 'overall quality')
      unless image_paths.all? { |p| File.exist?(p) }
        raise ArgumentError, "All images must exist"
      end
      
      prompt = "Rank these images by #{criteria}. Provide ranking with explanations."
      
      response = @llm.ask_with_images(
        prompt,
        images: image_paths,
        model: 'llava'
      )
      
      parse_ranking(response, image_paths)
    end
    
    # Find differences between images
    def diff(image1_path, image2_path)
      compare(image1_path, image2_path, aspect: 'differences')
    end
    
    # Assess similarity between images
    def similarity(image1_path, image2_path)
      result = compare(image1_path, image2_path, aspect: 'similarity')
      result[:similarity_score]
    end
    
    private
    
    # Build comparison prompt
    def build_comparison_prompt(aspect)
      base = "Compare these two images in detail."
      
      case aspect
      when 'differences'
        "#{base} Focus on what's different between them."
      when 'similarity'
        "#{base} Focus on similarities. Rate similarity 0-100."
      when 'quality'
        "#{base} Which has better technical quality? Consider composition, lighting, sharpness."
      when 'composition'
        "#{base} Compare composition, framing, and visual balance."
      when 'colors'
        "#{base} Compare color palettes, saturation, and color harmony."
      when 'mood'
        "#{base} Compare emotional tone and atmosphere."
      else
        "#{base} Consider composition, colors, mood, quality, and key differences."
      end
    end
    
    # Parse comparison response
    def parse_comparison(response)
      # Extract structured data from natural language response
      result = {
        raw_response: response,
        differences: extract_list(response, /differences?:?\s*/i),
        similarities: extract_list(response, /similarities?:?\s*/i),
        winner: extract_winner(response),
        similarity_score: extract_score(response),
        key_observations: extract_observations(response)
      }
      
      result
    end
    
    # Parse ranking response
    def parse_ranking(response, image_paths)
      # Extract ranking from response
      rankings = []
      
      image_paths.each_with_index do |path, idx|
        # Look for mentions of image number
        if response =~ /image\s*#{idx + 1}/i
          rank = response.scan(/\#(\d+)/).flatten.first&.to_i || (idx + 1)
          rankings << { path: path, rank: rank, index: idx }
        end
      end
      
      {
        raw_response: response,
        rankings: rankings.sort_by { |r| r[:rank] },
        winner: rankings.min_by { |r| r[:rank] }
      }
    end
    
    # Extract list items from text
    def extract_list(text, pattern)
      section = text[pattern..-1]
      return [] unless section
      
      # Find bullet points or numbered lists
      items = section.scan(/^\s*[-*•\d.]\s+(.+)$/m).flatten
      items.map(&:strip).first(5)  # Limit to 5 items
    end
    
    # Extract winner from comparison
    def extract_winner(text)
      if text =~ /image\s*1.*better/i || text =~ /first.*better/i
        1
      elsif text =~ /image\s*2.*better/i || text =~ /second.*better/i
        2
      elsif text =~ /similar|equal|tie/i
        nil
      else
        nil
      end
    end
    
    # Extract numeric score
    def extract_score(text)
      # Look for percentage or score out of 100
      if text =~ /(\d+)%/
        $1.to_i
      elsif text =~ /(\d+)\s*(?:out of|\/)\s*100/
        $1.to_i
      else
        nil
      end
    end
    
    # Extract key observations
    def extract_observations(text)
      # Get first few sentences as observations
      sentences = text.split(/[.!?]+/).map(&:strip).reject(&:empty?)
      sentences.first(3)
    end
  end
end
