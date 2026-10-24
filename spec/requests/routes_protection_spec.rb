# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Routes protection", type: :request do
  # Every route under /projects/:uuid, taken from the router so a new project
  # route is covered without anyone remembering to add it here. PUT repeats PATCH.
  ZERO_UUID = "00000000-0000-0000-0000-000000000000"
  PROJECT_ROUTES = Rails.application.routes.routes.filter_map do |route|
    spec = route.path.spec.to_s.delete_suffix("(.:format)")
    verb = route.verb.to_s
    next unless spec.match?(%r{\A/projects/:(project_)?uuid(/|\z)}) && %w[GET POST PATCH DELETE].include?(verb)

    [ verb, spec, route.requirements ]
  end.freeze

  # Routes that answer someone without access differently from "not found".
  # Rate limits are for Logister admins, so anyone else is sent home with a notice.
  ADMIN_ONLY_CONTROLLERS = %w[project_rate_limits].freeze

  # A value for each path segment that the route's own constraints accept.
  def project_route_path(spec, requirements, project)
    nested = spec.start_with?("/projects/:project_uuid/")
    spec.sub(nested ? ":project_uuid" : ":uuid", project.uuid).gsub(/:([a-z_]+)/) do
      requirement = requirements[Regexp.last_match(1).to_sym]
      (requirement.is_a?(Regexp) && %w[receive_data api_key].find { |value| requirement.match?(value) }) || (nested ? ZERO_UUID : "x")
    end
  end

  def request_project_route(verb, spec, requirements, project)
    public_send(verb.downcase, project_route_path(spec, requirements, project), headers: { "Turbo-Frame" => "any" })
  end

  it "covers every project route" do
    expect(PROJECT_ROUTES.size).to be > 60
    expect(PROJECT_ROUTES.map(&:first).uniq).to contain_exactly("GET", "POST", "PATCH", "DELETE")
  end

  describe "a signed-out visitor" do
    it "is sent to sign in from every project route" do
      project = create(:project)
      unprotected = PROJECT_ROUTES.reject do |verb, spec, requirements|
        request_project_route(verb, spec, requirements, project)
        response.redirect? && response.location.end_with?(new_user_session_path)
      end

      expect(unprotected).to be_empty
    end

    it "is sent to sign in from the pages people use outside a project" do
      pages = {
        "dashboard" => -> { get dashboard_path },
        "project list" => -> { get projects_path },
        "new project" => -> { get new_project_path },
        "new project, one page" => -> { get new_project_quick_path },
        "new project, first step" => -> { get new_project_step_path("platform") },
        "create project" => -> { post projects_path, params: { project: { name: "Nope" } } },
        "profile" => -> { get profile_path },
        "delete a CLI token" => -> { delete profile_cli_access_token_path(ZERO_UUID) },
        "delete every CLI token" => -> { delete profile_cli_access_tokens_path },
        "admin users" => -> { get admin_users_path },
        "dismiss a notification" => -> { post dismiss_notification_path, params: { notification_key: "release_update:2.0.4" } }
      }

      unprotected = pages.reject do |_name, request|
        instance_exec(&request)
        response.redirect? && response.location.end_with?(new_user_session_path)
      end

      expect(unprotected.keys).to be_empty
    end
  end

  describe "someone with no access to a project" do
    it "finds nothing on any project route" do
      project = create(:project)
      outsider = create(:user)
      revealing = PROJECT_ROUTES.reject do |verb, spec, requirements|
        sign_in outsider # a 404 raised inside a request does not keep the session
        request_project_route(verb, spec, requirements, project)
        if ADMIN_ONLY_CONTROLLERS.include?(requirements[:controller])
          response.redirect? && response.location.end_with?(root_path)
        else
          response.status == 404
        end
      end

      expect(revealing).to be_empty
    end
  end

  describe "a viewer on someone else's project" do
    it "can open every page that only reads" do
      project = create(:project, name: "Read Only Project")
      viewer = create(:user)
      create(:project_membership, project: project, user: viewer, role: :viewer)
      sign_in viewer

      pages = {
        "overview" => project_path(project),
        "issues" => inbox_project_path(project),
        "events" => activity_project_path(project),
        "charts" => insights_project_path(project),
        "performance" => performance_project_path(project),
        "monitors" => monitors_project_path(project),
        "deployments" => deployments_project_path(project),
        "archive" => archives_project_path(project),
        "setup" => setup_project_path(project),
        "settings" => settings_project_path(project)
      }
      unreadable = pages.reject do |_name, path|
        get path
        response.successful? && response.body.include?("Read Only Project")
      end

      expect(unreadable.keys).to be_empty
    end
  end

  # What each membership role may change on a shared project. Members (the
  # `viewer` enum value, labelled "Member") triage; project admins also manage
  # keys, access, and integrations; only the owner edits, archives, or deletes.
  # Each action runs against a fresh project so earlier actions cannot mask a 404.
  describe "role permissions on a shared project" do
    TRIAGE_ACTIONS = {
      "resolve an issue" => ->(project, group) { patch resolve_project_error_group_path(project, group) },
      "ignore an issue" => ->(project, group) { patch ignore_project_error_group_path(project, group) },
      "archive an issue" => ->(project, group) { patch archive_project_error_group_path(project, group) },
      "reopen an issue" => ->(project, group) { patch reopen_project_error_group_path(project, group) },
      "assign an issue" => ->(project, group) { patch project_error_group_assignment_path(project, group), params: { assigned_user_id: project.user.uuid } },
      "unassign an issue" => ->(project, group) { delete project_error_group_assignment_path(project, group) },
      "link an external issue" => ->(project, group) { post project_error_group_external_links_path(project, group), params: { error_group_external_link: { url: "https://tracker.example.com/T-1" } } },
      "change their own notification settings" => ->(project, _group) { patch project_notification_preference_path(project), params: { project_notification_preference: { digest_frequency: "daily" } } }
    }.freeze

    MANAGER_ACTIONS = {
      "create an API key" => ->(project, _group) { post project_api_keys_path(project), params: { api_key: { name: "role check" } } },
      "share the project" => ->(project, _group) { post project_project_memberships_path(project), params: { project_membership: { email: "nobody@example.com" } } },
      "change data retention" => ->(project, _group) { patch project_retention_policy_path(project), params: { project_retention_policy: { mode: "default" } } },
      "change integration settings" => ->(project, _group) { patch project_integration_setting_path(project), params: { project_integration_setting: { enabled: "0" } } },
      "mark a setup step not needed" => ->(project, _group) { post project_setup_skips_path(project), params: { key: "linked_projects" } }
    }.freeze

    OWNER_ACTIONS = {
      "edit the project" => ->(project, _group) { patch project_path(project), params: { project: { name: "Renamed" } } },
      "archive the project" => ->(project, _group) { patch archive_project_path(project) },
      "delete the project" => ->(project, _group) { delete project_path(project) }
    }.freeze

    def allowed_actions_for(role, actions)
      actions.select do |_name, action|
        project = create(:project)
        group = create(:error_group, :with_occurrence, project: project)
        member = create(:user)
        create(:project_membership, project: project, user: member, role: role)
        sign_in member

        instance_exec(project, group, &action)
        response.status != 404
      end.keys
    end

    it "labels the viewer role as Member" do
      expect(ProjectMembership.role_options).to eq([ [ "Member", "viewer" ], [ "Admin", "admin" ] ])
    end

    it "lets a Member triage issues and nothing more" do
      expect(allowed_actions_for(:viewer, TRIAGE_ACTIONS)).to match_array(TRIAGE_ACTIONS.keys)
      expect(allowed_actions_for(:viewer, MANAGER_ACTIONS)).to be_empty
      expect(allowed_actions_for(:viewer, OWNER_ACTIONS)).to be_empty
    end

    it "lets an Admin triage and manage the project, but not edit, archive, or delete it" do
      expect(allowed_actions_for(:admin, TRIAGE_ACTIONS)).to match_array(TRIAGE_ACTIONS.keys)
      expect(allowed_actions_for(:admin, MANAGER_ACTIONS)).to match_array(MANAGER_ACTIONS.keys)
      expect(allowed_actions_for(:admin, OWNER_ACTIONS)).to be_empty
    end

    it "makes a Member's triage change the issue" do
      project = create(:project)
      group = create(:error_group, :with_occurrence, project: project)
      member = create(:user)
      create(:project_membership, project: project, user: member, role: :viewer)
      sign_in member

      patch resolve_project_error_group_path(project, group)

      expect(group.reload).to be_resolved
    end
  end

  describe "shared member permissions" do
    before { sign_in users(:two) }

    it "cannot create api keys on shared project" do
      expect {
        post project_api_keys_path(projects(:one)), params: { api_key: { name: "forbidden" } }
      }.not_to change(ApiKey, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "cannot manage project memberships on shared project" do
      expect {
        post project_project_memberships_path(projects(:one)),
             params: { project_membership: { email: "one@example.com" } }
      }.not_to change(ProjectMembership, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
