# frozen_string_literal: true

class AiController < ApplicationController
  before_action :require_authentication

  def analyze_item
    item = Current.user.items.find(params[:id])
    result = WardrobeAiService.new(Current.user).analyze_joy(item)
    item.update!(spark_joy: result["sparks_joy"]) if result["sparks_joy"].in?([true, false])
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("item_#{item.id}_analysis", partial: "ai/analysis", locals: { result: result, item: item }) }
      format.json { render json: result }
    end
  end

  def tag_item
    item = Current.user.items.find(params[:id])
    result = WardrobeAiService.new(Current.user).enclothed_cognition_tag(item)
    item.update!(mood_effect: result["mood_effect"], life_phase: result["life_phase"])
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("item_#{item.id}_tags", partial: "ai/item_tags", locals: { item: item.reload, result: result }) }
      format.html { redirect_to item }
    end
  end

  def suggest_outfits
    @suggestions = WardrobeAiService.new(Current.user).suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )
  end

  def declutter_guide
    @candidates = WardrobeAiService.new(Current.user).declutter_candidates
  end

  def capsule
    @result = WardrobeAiService.new(Current.user).capsule_optimizer
  end

  def color_palette
    @result = WardrobeAiService.new(Current.user).color_palette_analysis
  end

  def search
    @query = params[:q].to_s.strip
    if @query.present?
      result = WardrobeAiService.new(Current.user).natural_language_search(@query)
      ids = Array(result["item_ids"])
      @items = Current.user.items.where(id: ids)
      @explanation = result["explanation"]
    else
      @items = Current.user.items.none
    end
  end

  def mood_board
    @description = params[:description].to_s.strip
    if @description.present?
      result = WardrobeAiService.new(Current.user).mood_board_match(@description)
      ids = Array(result["item_ids"])
      @items = Current.user.items.where(id: ids)
      @outfit_name = result["outfit_name"]
      @reasoning = result["description"]
    end
  end

  def occasion_map
    @coverage = Item::OCCASIONS.each_with_object({}) do |occ, h|
      h[occ] = Current.user.items.by_occasion(occ).to_a
    end
  end

  def style_profile
    if request.post? || params[:answers].present?
      answers = params[:answers] || {}
      result = WardrobeAiService.new(Current.user).infer_style_profile(answers)
      profile = Current.user.style_profile || Current.user.build_style_profile
      aesthetic = result["aesthetic"].presence || "minimal"
      profile.update!(style_preferences: aesthetic, body_type: answers[:body_type])
      redirect_to user_path(Current.user), notice: "Style profile set to #{aesthetic}"
    end
  end

  def packing_list
    if params[:duration].present?
      @duration = params[:duration].to_i
      @climate = params[:climate].to_s
      @result = WardrobeAiService.new(Current.user).suggest_packing_list(@duration, @climate)
      # auto create packing list demo
      if @result["outfits"]
        list = Current.user.packing_lists.create!(name: "#{@climate} #{ @duration }d trip", starts_on: Date.today, ends_on: Date.today + @duration)
        # would link items if matched
      end
    end
  end

  def generate_outfit
    suggestions = WardrobeAiService.new(Current.user).suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )
    suggestion = Array(suggestions).first
    return redirect_to(ai_suggest_outfits_path, alert: t("amber.outfits.no_vision", default: "No vision suggestion generated")) unless suggestion

    outfit = create_outfit_from_vision_suggestion(suggestion)
    redirect_to(outfit, notice: t("amber.outfits.vision_created", default: "Outfit created from MASTER vision"))
  end

  private

  def create_outfit_from_vision_suggestion(suggestion)
    name = suggestion["name"].presence || "Vision outfit"
    outfit = Current.user.outfits.create!(
      name: name,
      description: suggestion["description"].to_s,
      season: params[:season],
      occasion: params[:occasion],
    )
    titles = Array(suggestion["items"])
    titles.each_with_index do |title, index|
      key = title.to_s.split("(").first.strip.downcase
      item = Current.user.items.where("lower(title) LIKE ?", "%#{key}%").first
      item ||= Current.user.items.joy.active_wardrobe.first
      outfit.outfit_items.create!(item: item, position: index) if item
    end
    outfit
  end
end
