class ProjectLinkAudit < ApplicationRecord
  belongs_to :source_project, class_name: "Project"
  belongs_to :target_project, class_name: "Project"
  belongs_to :actor, class_name: "User", optional: true
end
