require "scientist"

class MyWidget
  include Scientist

  def allows?(user)
    science "widget-permissions" do |e|
      e.use   { model.check_user(user).valid? }
      e.try   { user.can?(:read, model) }
    end
  end
end
