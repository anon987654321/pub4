# frozen_string_literal: true

require "minitest/autorun"

# `isolate_namespace Tv` strips the namespace from model_name, so
# `form_with model: @video` posts video[title] — not tv_video[title]. Sixteen
# controllers across the five engines required the namespaced key their own
# forms could not produce, so every one of those submissions answered 400
# ParameterMissing: publishing a listing, writing a review, saving an address,
# creating a dating profile, a playlist, a restaurant, a tv channel or a video.
#
# Measured 2026-08-19 against the real route: posting listing[...] answered 400
# and marketplace_listing[...] answered 302, while the rendered form's own field
# names were listing[title], listing[price_cents], listing[category_id].
#
# The namespaced key is legitimate when a form asks for it by name
# (`form_with url: …, scope: :tv_comment`), which several do — so this asserts
# agreement between the two rather than banning the long key outright.
class EngineParamKeyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ENGINES = %w[marketplace dating playlist takeaway tv maps].freeze

  def engine_root(engine) = File.join(ROOT, "brgen/engines", engine)

  def scoped_keys(engine)
    Dir.glob(File.join(engine_root(engine), "app/views/**/*.erb"))
       .flat_map { |path| File.read(path).scan(/scope:\s*:([a-z_]+)/).flatten }
       .to_set
  end

  def required_keys(engine)
    Dir.glob(File.join(engine_root(engine), "app/controllers/**/*.rb")).flat_map do |path|
      File.read(path).scan(/params\.(?:require|dig)\(:(#{engine}_[a-z_]+)/).flatten
          .map { |key| [ path.sub("#{ROOT}/", ""), key ] }
    end
  end

  def test_every_namespaced_param_key_is_one_a_form_actually_posts
    offenders = ENGINES.flat_map do |engine|
      scoped = scoped_keys(engine)
      required_keys(engine).reject { |_path, key| scoped.include?(key) }
                           .map { |path, key| "#{path}: reads :#{key}, and no form in the engine scopes to it — an isolated engine posts :#{key.sub("#{engine}_", '')}" }
    end

    assert_empty offenders,
                 "param keys no engine form produces:\n  #{offenders.join("\n  ")}"
  end

  # The detector has to be able to see the shape it exists for.
  def test_it_names_a_key_no_form_scopes_to
    engine = "marketplace"
    found = "params.require(:marketplace_listing).permit(:title)".scan(/params\.(?:require|dig)\(:(#{engine}_[a-z_]+)/).flatten

    assert_equal [ "marketplace_listing" ], found
    assert_not_includes scoped_keys(engine), "marketplace_listing"
  end

  def assert_not_includes(collection, member)
    refute_includes collection, member
  end
end
