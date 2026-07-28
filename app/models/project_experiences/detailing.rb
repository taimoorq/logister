# frozen_string_literal: true

module ProjectExperiences::Detailing
  def detail_sections(event:, occurrences_count:, related_logs_count:)
    [
      section(:context, "Context"),
      section(:stacktrace, stacktrace_tab_label(event)),
      section(:occurrences, "Occurrences (#{occurrences_count})"),
      section(:related_logs, "Related logs (#{related_logs_count})")
    ]
  end

  def normalize_detail_tab(value, event: nil, occurrences_count: 0, related_logs_count: 0)
    sections = detail_sections(event: event, occurrences_count: occurrences_count, related_logs_count: related_logs_count)
    allowed = sections.filter_map { |section| section.key.to_s }
    value.to_s.presence_in(allowed) || default_detail_tab
  end

  def default_detail_tab
    "stacktrace"
  end

  def stacktrace_tab_label(event)
    return "Details" if %w[python javascript dotnet].include?(project.integration_kind) && event&.log?

    "Stacktrace"
  end

  def stacktrace_partial(event)
    return "project_events/python_log_event" if project.integration_python? && event.log?
    return "project_events/javascript_log_event" if project.integration_javascript? && event.log?
    return "project_events/dotnet_log_event" if project.integration_dotnet? && event.log?
    return "project_events/cfml_stacktrace" if project.integration_cfml?
    return "project_events/javascript_stacktrace" if project.integration_javascript?
    return "project_events/python_stacktrace" if project.integration_python?
    return "project_events/dotnet_stacktrace" if project.integration_dotnet?

    "project_events/ruby_stacktrace"
  end

  def event_presenter(event)
    nil
  end
end
