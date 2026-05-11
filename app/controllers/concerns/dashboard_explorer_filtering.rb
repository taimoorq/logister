module DashboardExplorerFiltering
  extend ActiveSupport::Concern

  MAX_EXPLORER_ENVIRONMENT_FILTER_LENGTH = 80

  private

  def dashboard_explorer_filters(project_ids)
    event_type = params[:event_type].to_s
    project_id = params[:project_id].to_i
    environment = params[:environment].to_s.strip.first(MAX_EXPLORER_ENVIRONMENT_FILTER_LENGTH)
    occurred_on = dashboard_explorer_occurred_on

    {}.tap do |filters|
      filters[:event_type] = event_type if IngestEvent.event_types.key?(event_type)
      filters[:project_id] = project_id if project_ids.include?(project_id)
      filters[:environment] = environment if environment.present?
      filters[:occurred_on] = occurred_on if occurred_on.present?
    end
  end

  def dashboard_explorer_query_params(filters)
    {}.tap do |query|
      query[:event_type] = filters[:event_type] if filters[:event_type].present?
      query[:project_id] = filters[:project_id] if filters[:project_id].present?
      query[:environment] = filters[:environment] if filters[:environment].present?
      query[:occurred_on] = filters[:occurred_on].iso8601 if filters[:occurred_on].present?
    end
  end

  def dashboard_explorer_filter_labels(filters, projects_by_id)
    [].tap do |labels|
      if filters[:event_type].present?
        labels << helpers.dashboard_event_type_label(filters[:event_type])
      end

      if filters[:project_id].present?
        labels << (projects_by_id[filters[:project_id]]&.name || "Project")
      end

      labels << filters[:environment] if filters[:environment].present?
      labels << filters[:occurred_on].to_fs(:long) if filters[:occurred_on].present?
    end
  end

  def dashboard_explorer_occurred_on
    return if params[:occurred_on].blank?

    date = Date.iso8601(params[:occurred_on].to_s)
    window_start_date = (Dashboard::EXPLORER_WINDOW_DAYS - 1).days.ago.to_date
    current_date = Time.current.to_date

    date if date.between?(window_start_date, current_date)
  rescue ArgumentError
    nil
  end
end
