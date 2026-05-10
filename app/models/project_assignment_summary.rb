# Summarizes unresolved assignment workload for one project.
class ProjectAssignmentSummary
  attr_reader :project

  def initialize(project)
    @project = project
  end

  def open_count_for(user)
    open_counts_by_user_id[user.id].to_i
  end

  def open_counts_by_user_id
    @open_counts_by_user_id ||= project.error_groups
                                       .unresolved
                                       .where.not(assigned_user_id: nil)
                                       .group(:assigned_user_id)
                                       .count
  end

  def unassigned_open_count
    @unassigned_open_count ||= project.error_groups.unresolved.unassigned.count
  end

  def assigned_open_count
    open_counts_by_user_id.values.sum
  end

  def total_open_count
    assigned_open_count + unassigned_open_count
  end
end
