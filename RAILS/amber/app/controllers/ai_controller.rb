# frozen_string_literal: true

require "open3"

class AiController < ApplicationController
  before_action :require_real_user

  # suggest_outfits is a GET that asks a model for outfits and, when the MASTER
  # photograph bridge is enabled, renders a photograph in this request. The
  # write throttle does not see a GET, so it carries its own limit, and each
  # photograph is one bounded subprocess: a 1 GB box cannot hold a request open
  # on an unbounded render.
  MASTER_PHOTOGRAPHS_PER_REQUEST = 1
  MASTER_PHOTOGRAPH_TIMEOUT = 120

  rate_limit to: 10, within: 10.minutes, only: :suggest_outfits,
             by: -> { "u#{Current.user&.id}" },
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
    RecommendOutfitsJob.perform_later(Current.user.id, occasion: params[:occasion], season: params[:season]) if defined?(RecommendOutfitsJob)
    service = WardrobeAi.new(Current.user)
    @ai_available = service.available?
    @suggestions = service.suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )
    @master_photo = WardrobeAi.master_photograph_available?

    return unless @master_photo

    master_root = Operator::DeployPaths.master_root.to_s
    @suggestions.select { |s| s.is_a?(Hash) }.first(MASTER_PHOTOGRAPHS_PER_REQUEST).each do |s|
      combo = "professional fashion photography of outfit '#{s['name']}' with #{Array(s['items']).join(', ')}. #{s['description']}. model, kodak portra, cinematic"
      begin
        out = photograph(master_root, combo)
        if out =~ /postpro.*(output\/[^\s]+_postpro)/
          pdir = File.join(master_root, $1)
          imgf = Dir.glob(File.join(pdir, "*.{jpg,jpeg,png}")).first
          if imgf && File.exist?(imgf)
            outfit = Current.user.outfits.create!(name: s["name"], description: s["description"].to_s)
            Array(s["items"]).each do |tit|
              key = tit.to_s.split("(").first.strip.downcase
              it = Current.user.items.where("lower(title) LIKE ?", "%#{key}%").first || Current.user.items.joy.active_wardrobe.first
              outfit.outfit_items.create!(item: it) if it
            end
            outfit.image.attach(io: File.open(imgf), filename: "visual.jpg")
            s["outfit_id"] = outfit.id
          end
        end
      rescue StandardError => e
        Rails.logger.warn("MASTER photograph for suggestion failed: #{e.message}")
      end
    end
  end

  def declutter_guide
    @candidates = WardrobeAi.new(Current.user).declutter_candidates
  end

  def capsule
    @result = WardrobeAi.new(Current.user).capsule_optimizer
    @ai_available = WardrobeAi.configured?
  end

  def color_palette
    @result = WardrobeAi.new(Current.user).color_palette_analysis
    @swatches = Current.user.items.where.not(color: [ nil, "" ]).limit(24).pluck(:title, :color)
  end

  def search
    @query = params[:q].to_s.strip
    @ai_available = WardrobeAi.configured?
    if @query.present?
      result = WardrobeAi.new(Current.user).natural_language_search(@query)
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
    if request.post? || params[:answers].present?
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
    if params[:duration].present?
      @duration = params[:duration].to_i
      @climate = params[:climate].to_s
      @result = WardrobeAi.new(Current.user).suggest_packing_list(@duration, @climate)
      if @result["outfits"]
        list = Current.user.packing_lists.create!(
          name: "#{@climate} #{@duration}d trip",
          starts_on: Date.current,
          ends_on: Date.current + @duration
        )
        Array(@result["outfits"]).each do |outfit|
          Array(outfit["items"]).each do |title|
            key = title.to_s.split("(").first.strip.downcase
            item = Current.user.items.where("lower(title) LIKE ?", "%#{key}%").first
            next unless item

            list.packing_list_items.find_or_create_by!(item: item) { |pli| pli.quantity = 1 }
          end
        end
        @packing_list = list
      end
    end
  end

  def generate_outfit
    suggestions = WardrobeAi.new(Current.user).suggest_outfits(
      occasion: params[:occasion], season: params[:season]
    )
    suggestion = Array(suggestions).first
    return redirect_to(ai_suggest_outfits_path, alert: t("flash.no_outfit_suggestion")) unless suggestion

    outfit = create_outfit_from_vision_suggestion(suggestion)
    redirect_to(outfit, notice: t("flash.outfit_created"))
  end

  private

  # Argv array, never a shell string: the prompt carries text a model wrote.
  # The child is killed at the timeout and its output so far is returned.
  def photograph(master_root, prompt)
    # brakeman :ignore Execute
    Open3.popen2e("bundle", "exec", "ruby", "bin/cli", "photograph", prompt, chdir: master_root) do |stdin, output, wait|
      stdin.close
      reader = Thread.new { output.read }
      unless wait.join(MASTER_PHOTOGRAPH_TIMEOUT)
        Process.kill("TERM", wait.pid)
        wait.join(5) || Process.kill("KILL", wait.pid)
      end
      reader.value.to_s
    end
  end

  def create_outfit_from_vision_suggestion(suggestion)
    name = suggestion["name"].presence || "Suggested outfit"
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
