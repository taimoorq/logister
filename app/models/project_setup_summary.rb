# frozen_string_literal: true

# The cheap, viewer-independent view of setup used on every project page (the
# header chip) and on project lists. It is computed from a viewer-less plan and
# cached briefly so navigation never re-reads evidence on each request.
#
# Steps waiting on an instance setting are not counted or suggested: a project
# user cannot fix them, and they would nag every project on an instance that has
# not enabled the service. They still appear, as blocked, in the Setup hub.
class ProjectSetupSummary
  # The header chip links to the Setup hub, which knows who is looking; nothing
  # viewer-specific is stored here because this summary is shared.
  Focus = Data.define(:key, :label, :chip_label, :state)

  attr_reader :live, :required_done, :required_total, :open_recommended, :focus, :attention

  CACHE_VERSION = "project_setup_summary_v1"
  CACHE_TTL = 5.minutes

  # Read on every project page through the header chip, so it is memoized for the
  # request and shared briefly across requests. The Setup hub and skip decisions
  # call `expire`, so the person who just changed something sees it immediately.
  def self.for(project)
    ProjectReadCache.fetch(project, :setup_summary) do
      cached(project) { from_plan(ProjectSetupPlan.for(project)) }
    end
  end

  def self.expire(project)
    Rails.cache.delete(cache_key(project))
  rescue StandardError => error
    Rails.logger.warn("Setup summary cache unavailable: #{error.class}")
  end

  def self.cache_key(project)
    [ CACHE_VERSION, project.id, project.updated_at.to_i ]
  end

  def self.cached(project)
    computing = false
    computed = false
    result = nil
    Rails.cache.fetch(cache_key(project), expires_in: CACHE_TTL) do
      computing = true
      result = yield
      computing = false
      computed = true
      result
    end
  rescue StandardError => error
    raise if computing

    Rails.logger.warn("Setup summary cache unavailable: #{error.class}")
    computed ? result : yield
  end
  private_class_method :cached

  def self.from_plan(plan)
    new(
      live: plan.live?,
      required_done: plan.required_done_count,
      required_total: plan.required_total,
      open_recommended: plan.open_recommended_items.size,
      focus: focus_for(plan.next_item),
      attention: focus_for(plan.attention_item)
    )
  end

  def self.focus_for(item)
    return unless item

    Focus.new(key: item.key, label: item.label, chip_label: chip_label(item), state: item.state)
  end
  private_class_method :focus_for

  def self.chip_label(item)
    case item.state
    when :failed then "#{item.label} failed"
    when :stale then "#{item.label} is stale"
    else item.step.chip_label
    end
  end

  def initialize(live:, required_done:, required_total:, open_recommended:, focus:, attention:)
    @live = live
    @required_done = required_done
    @required_total = required_total
    @open_recommended = open_recommended
    @focus = focus
    @attention = attention
    freeze
  end

  def live? = live

  # Nothing to do: live, nothing failing, no recommended step left.
  def quiet?
    live? && attention.nil? && open_recommended.zero?
  end

  # What the header chip shows.
  def state
    return :attention if attention
    return :incomplete unless live?

    open_recommended.positive? ? :live_with_steps : :live
  end
end
