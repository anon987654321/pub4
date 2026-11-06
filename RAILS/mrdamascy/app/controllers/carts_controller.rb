# frozen_string_literal: true

class CartsController < ApplicationController
  rescue_from Cart::InvalidLine, with: :refuse_line
  rescue_from Cart::SoldOut, with: :refuse_sold_out

  def show
    @cart = current_cart
    @lines = @cart.cart_items.includes(:menu_item).order(:id)
    @promo = cart_promo
  end

  # Quick-add from the menu (APP_SPEC §6): a Turbo Stream refreshes the cart
  # bar, tab badge and toast in place; a no-JS/Turbo client falls back to a
  # redirect to the cart.
  def add_item
    item = MenuItem.find(params[:menu_item_id])
    bar_was_hidden = current_cart.cart_items.empty? # the bar only renders when count > 0
    current_cart.add_item!(
      item,
      quantity_param,
      option_ids: Array(params[:option_ids]),
      note: params[:note].presence
    )

    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = t("flash.added", name: item.name)
        render turbo_stream: cart_streams(bar_appeared: bar_was_hidden)
      end
      format.html { redirect_to cart_path, notice: t("flash.added", name: item.name) }
    end
  end

  # "Yalla igjen" on the menu: the whole last order back in the cart with
  # one post.
  def reorder
    order = current_user&.orders&.find_by(id: params[:order_id])
    return redirect_to(root_path, alert: t("flash.not_found")) unless order

    left_out = order.reorder_into!(current_cart)
    redirect_to cart_path, notice: left_out.zero? ? t("flash.reordered") : t("flash.reordered_partly")
  end

  # Qty stepper on the cart page; 0 or less removes the line.
  def update_item
    line = current_cart.cart_items.find(params[:line_id])
    quantity = quantity_param

    if quantity <= 0
      line.destroy!
      notice = t("flash.removed")
    else
      line.update!(quantity: quantity.clamp(1, Cart::MAX_QUANTITY))
      notice = t("cart.updated")
    end

    respond_with_line_change(notice)
  end

  def remove_item
    line = current_cart.cart_items.find(params[:line_id])
    line.destroy!

    respond_with_line_change(t("flash.removed"), turbo_stream.remove("cart_item_#{line.id}"))
  end

  private

  # A stepper or remove tap answers with the re-rendered lines and summary
  # plus the shared pay-bar, badge and toast streams; no-JS clients reload
  # the cart.
  def respond_with_line_change(notice, *streams)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = notice
        render turbo_stream: streams + [ cart_contents_stream ] + cart_streams
      end
      format.html { redirect_to cart_path, notice: }
    end
  end

  # The line was refused before anything was written; send the guest back to
  # the dish so the sheet shows what can be picked.
  def refuse_line
    redirect_to menu_item_path(params[:menu_item_id]), alert: t("flash.line_invalid"), status: :see_other
  end

  def refuse_sold_out
    redirect_to root_path, alert: t("menu.sold_out"), status: :see_other
  end

  def quantity_param
    (params[:quantity] || params[:qty] || 1).to_i
  end

  # The shared stream contract with the layout (APP_SPEC §7):
  # - shared/_cart_bar renders its own root with dom id "cart_bar" — replaced
  #   when present, appended to <body> when the first item just made it exist;
  # - the tab badge is the layout's span#cart_count;
  # - shared/_toast renders flash messages into the layout's div#toasts,
  #   whose content each stream replaces.
  def cart_streams(bar_appeared: false)
    bar_locals = { cart_count: current_cart.total_quantity, cart_total_ore: current_cart.subtotal_ore }
    streams = []
    if bar_appeared
      streams << turbo_stream.append(nil, targets: "body", partial: "shared/cart_bar", locals: bar_locals)
    else
      streams << turbo_stream.replace("cart_bar", partial: "shared/cart_bar", locals: bar_locals)
    end
    streams << cart_badge_stream
    streams << turbo_stream.update("toasts", partial: "shared/toast")
    streams
  end

  # The badge names the code checkout will apply, or none at all.
  def cart_promo
    PromoApplier.call(subtotal_ore: current_cart.subtotal_ore, delivery_mode: current_cart.delivery_mode,
                      user: current_user)[:promo]
  end

  # The stepper changed a line's quantity, sum and the subtotal; the page's
  # lines and summary are re-rendered from the cart as it now stands.
  def cart_contents_stream
    cart = current_cart
    cart.cart_items.reset
    turbo_stream.replace("cart_contents", partial: "carts/contents", locals: { cart:, promo: cart_promo })
  end

  def cart_badge_stream
    count = current_cart.total_quantity
    badge = view_context.tag.span(count, id: "cart_count", class: "tab-badge", hidden: count.zero?)
    turbo_stream.replace("cart_count", badge)
  end
end
