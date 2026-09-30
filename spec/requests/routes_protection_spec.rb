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
