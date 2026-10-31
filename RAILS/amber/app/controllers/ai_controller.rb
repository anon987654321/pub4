# frozen_string_literal: true

require "shared/contracts"
Shared::Contracts.require_contract("studio")

class AiController < ApplicationController
  include PremiumGate

  before_action :require_real_user
  premium_only :suggest_outfits, :generate_outfit, :declutter_guide, :packing_list

  # GET actions only suggest. The explicit generate_outfit POST owns persistence
  # and the optional single STUDIO photograph.

  rate_limit to: 10, within: 10.minutes, only: %i[suggest_outfits generate_outfit],
             by: -> { Current.user ? "u#{Current.user.id}" : "ip#{request.remote_ip}" },
             with: -> { redirect_to items_path, alert: t("shared.flash.rate_limited") }

  def analyze_item
    item = Current.user.items.find(params[:id])
    result = WardrobeAi.new(Current.user).analyze_joy(item)
    item.update!(spark_joy: result["sparks_joy"]) if result["sparks_joy"].in?([ true, false ])
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("item_#{item.id}_analysis", partial: "ai/analysis", locals: { result: result, item: item }) }
      format.html { redirect_to item, notice: result["source"] == "heuristic" ? t("flash.joy_analysis_heuristic") : t("flash.joy_analysis_ai") }
      format.json { render json: result }
    end
  end

  def tag_item
    item = Current.user.items.find(params[:id])
    result = WardrobeAi.new(Current.user).enclothed_cognition_tag(item)
    item.update!(mood_effect: result["mood_effect"], life_phase: result["life_phase"])
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("item_#{item.id}_tags", partial: "ai/item_tags", locals: { item: item.reload, result: result }) }
      format.html { redirect_to item }
    end
  end

  def suggest_outfits
    service = WardrobeAi.new(Current.user)
    @ai_available = service.available?
    @suggestions = service.suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )
    # GET is read-only. Optional photography belongs to the explicit save POST.
    @studio_photo = service.external_processing_allowed? && WardrobeAi.studio_photograph_available?
  end

  def declutter_guide
    @candidates = WardrobeAi.new(Current.user).declutter_candidates
  end

  def capsule
    service = WardrobeAi.new(Current.user)
    @result = service.capsule_optimizer
    @ai_available = service.available?
  end

  def color_palette
    @result = WardrobeAi.new(Current.user).color_palette_analysis
    @swatches = Current.user.items.where.not(color: [ nil, "" ]).limit(24).pluck(:title, :color)
  end

  def search
    @query = params[:q].to_s.strip
    service = WardrobeAi.new(Current.user)
    @ai_available = service.available?
    if @query.present?
      result = service.natural_language_search(@query)
      ids = Array(result["item_ids"])
      @items = Current.user.items.where(id: ids)
      @explanation = result["explanation"]
      @source = result["source"]
    else
      @items = Current.user.items.none
    end
  end

  def mood_board
    @description = params[:description].to_s.strip
    if @description.present?
      result = WardrobeAi.new(Current.user).mood_board_match(@description)
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

  # Writes a StylePreference, not the old table-less StyleProfile: preferences
  # are the backed concept (style_preferences table, User has_many, consumed by
  # OutfitCompatibility#preference_fit). The questionnaire sets *the* aesthetic,
  # so the previous one is replaced rather than accumulated — the table's unique
  # index is [user_id, kind, name], which would otherwise leave a user holding
  # several contradictory aesthetics.
  def style_profile
    if request.post?
      answers = params[:answers] || {}
      result = WardrobeAi.new(Current.user).infer_style_profile(answers)
      aesthetic = result["aesthetic"].presence || "minimal"

      StylePreference.transaction do
        Current.user.style_preferences.where(kind: :aesthetic).where.not(name: aesthetic).destroy_all
        Current.user.style_preferences
               .find_or_initialize_by(kind: :aesthetic, name: aesthetic)
               .update!(weight: 1.0, metadata: { body_type: answers[:body_type] }.compact)
      end

      redirect_to user_path(Current.user), notice: t("flash.style_profile_set", aesthetic: aesthetic)
    end
  end

  def packing_list
    # GET renders the form only. Saving a list is a deliberate POST.
    return unless request.post?

    @duration = Integer(params[:duration].to_s, exception: false)
    @duration = @duration ? @duration.clamp(1, 14) : 1
    @climate = params[:climate].to_s.presence_in(%w[hot cold mild rainy dry]) || "mild"
    @result = WardrobeAi.new(Current.user).suggest_packing_list(@duration, @climate)
    return unless @result["outfits"]

    list = Current.user.packing_lists.create!(
      name: "#{@climate} #{@duration}d trip",
      starts_on: Date.current,
      ends_on: Date.current + @duration
    )
    Array(@result["outfits"]).each do |outfit|
      ids = Array(outfit["item_ids"]).filter_map do |value|
        value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
      end.uniq
      Current.user.items.in_rotation.where(id: ids).find_each do |item|
        list.packing_list_items.find_or_create_by!(item:) { |pli| pli.quantity = 1 }
      end
    end
    @packing_list = list
  end

  def generate_outfit
    service = WardrobeAi.new(Current.user)
    suggestion = Array(service.suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )).first
    return redirect_to(ai_suggest_outfits_path, alert: t("flash.no_outfit_suggestion")) unless suggestion

    outfit = create_outfit_from_vision_suggestion(suggestion)
    return redirect_to(ai_suggest_outfits_path, alert: t("flash.no_outfit_suggestion")) unless outfit

    attach_studio_photo(outfit) if service.external_processing_allowed? && WardrobeAi.studio_photograph_available?
    redirect_to(outfit, notice: t("flash.outfit_created"))
  end

  private

  def create_outfit_from_vision_suggestion(suggestion)
    ids = Array(suggestion["item_ids"]).filter_map do |value|
      value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
    end.uniq
    items = Current.user.items.in_rotation.where(id: ids).to_a
    return if items.empty?

    outfit = Current.user.outfits.create!(
      name: suggestion["name"].presence || "Suggested outfit",
      description: suggestion["description"].to_s,
      season: params[:season],
      occasion: params[:occasion]
    )
    items.sort_by(&:id).each_with_index do |item, index|
      outfit.outfit_items.create!(item:, position: index)
    end
    outfit
  end

  def attach_studio_photo(outfit)
    prompt = "Professional fashion photography of the saved outfit '#{outfit.name}' with " \
             "#{outfit.items.map(&:title).join(', ')}. #{outfit.description}. " \
             "Model, Kodak Portra, editorial fashion photography."
    result = Contracts::Studio.photograph(prompt:)
    image_path = result["still"].to_s
    return unless File.file?(image_path)

    File.open(image_path, "rb") do |image|
      outfit.image.attach(io: image, filename: "amber-outfit-#{outfit.id}.jpg", content_type: "image/jpeg")
    end
  rescue StandardError => e
    Rails.logger.warn("STUDIO photograph for saved outfit failed: #{e.class}: #{e.message}")
  end
end
