# frozen_string_literal: true

require_relative "test_helper"

# STRONG_PARAMETERS closes principle_map's strong_parameters gap (detects
# mass_assignment_risk). RAILS is clean of both failure modes today, so the
# rule earns its place as a guard against regression rather than a backlog —
# which makes the negative direction as important to pin as the positive one.
class TestStrongParametersRule < Minitest::Test
  CONTROLLER = "/repo/app/controllers/users_controller.rb"

  def scanner
    @scanner ||= Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT)
  end

  def rule
    @rule ||= scanner.rules.find { |r| r.id.to_s == "STRONG_PARAMETERS" } ||
              raise("STRONG_PARAMETERS is not registered")
  end

  def findings(source, path: CONTROLLER)
    Array(rule.check("#{source}\n", path:))
  end

  def test_flags_raw_params_reaching_a_mass_assignment_sink
    [
      "User.new(params[:user])",
      "@post = Post.create(params[:post])",
      "@post = Post.create!(params[:post])",
      "@user.update(params[:user])",
      "@user.update!(params[:user])",
      "@user.assign_attributes(params[:user])",
    ].each do |line|
      refute_empty findings(line), "#{line.inspect} is mass assignment from raw params"
    end
  end

  def test_flags_permit_bang
    refute_empty findings("params.require(:user).permit!")
    refute_empty findings("attrs = params.permit!")
  end

  def test_quiet_on_permitted_attributes
    [
      "@user = User.new(user_params)",
      "params.require(:user).permit(:email, :name)",
      "@post = Post.find(params[:id])",
      "redirect_to params[:return_to]",
      "@q = params[:q].to_s",
    ].each do |line|
      assert_empty findings(line), "#{line.inspect} does not mass-assign"
    end
  end

  def test_scoped_to_rails_app_code
    line = "User.new(params[:user])"
    assert_empty findings(line, path: "/repo/test/models/user_test.rb")
    assert_empty findings(line, path: "/repo/lib/importer.rb")
    refute_empty findings(line, path: "/repo/app/services/signup.rb")
  end
end
