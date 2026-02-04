# Separation of Concerns

> Divide program into distinct sections, each addressing a separate concern.

tier: core
priority: 4
auto_fixable: false

## Anti-patterns (violations)

### mixed_concerns
- **Smell**: One module handles unrelated responsibilities
- **Example**: User class handles auth, email, and billing
- **Fix**: Split into UserAuth, UserMailer, UserBilling

### ui_logic_in_models
- **Smell**: Domain models contain presentation logic
- **Example**: `User#to_html` or formatting in ActiveRecord
- **Fix**: Use presenters/decorators for display logic

### business_logic_in_views
- **Smell**: Templates contain conditionals and calculations
- **Example**: `<% if user.age > 18 && user.verified? %>`
- **Fix**: Move logic to model/presenter, expose simple flags
