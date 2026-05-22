module ProductToursHelper
  def product_tour_scope_data(group, controllers: nil, auto_on_interaction: true)
    controller_names = Array(controllers).flat_map { |controller| controller.to_s.split }.compact_blank
    controller_names << "product-tour"
    actions = [ "turbo:before-cache@document->product-tour#beforeCache" ]
    actions.unshift("click->product-tour#startForNewUser:capture") if auto_on_interaction

    {
      controller: controller_names.uniq.join(" "),
      action: actions.join(" "),
      product_tour_group_value: group,
      product_tour_auto_on_interaction_value: auto_on_interaction
    }
  end

  def product_tour_frame_data(group, data: {}, controllers: nil, auto_on_interaction: true)
    frame_data = (data || {}).deep_symbolize_keys
    tour_data = product_tour_scope_data(group, controllers: controllers, auto_on_interaction: auto_on_interaction)

    %i[controller action].each do |token_key|
      tokens = [ frame_data[token_key], tour_data.delete(token_key) ].compact_blank
      frame_data[token_key] = tokens.join(" ") if tokens.any?
    end

    frame_data.merge(tour_data)
  end

  def product_tour_step_data(group, step)
    step_config = product_tour_step(group, step)

    {
      tg_group: group,
      tg_order: step_config.fetch(:order),
      tg_title: step_config.fetch(:title),
      tg_tour: step_config.fetch(:tour)
    }
  end

  def tour_help_button(label: t("product_tours.help_button.label"))
    render "shared/product_tour_help", label: label
  end

  private

  def product_tour_step(group, step)
    step_config = t("product_tours.steps.#{group}.#{step}", default: nil)
    step_config ||= t("product_tours.steps.shared.#{step}", default: nil)

    raise KeyError, "Missing product tour step for #{group}.#{step}" if step_config.blank?

    step_config.deep_symbolize_keys
  end
end
