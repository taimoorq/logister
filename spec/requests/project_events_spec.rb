# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project events", type: :request do
  describe "GET /projects/:project_uuid/events" do
    before { sign_in users(:one) }

    it "redirects to project when not a Turbo Frame request" do
      get project_events_path(projects(:one))
      expect(response).to redirect_to(project_path(projects(:one), filter: "unresolved", q: ""))
    end
  end

  describe "GET /projects/:project_uuid/events/:uuid" do
    context "when owner" do
      before { sign_in users(:one) }

      it "returns success and event detail" do
        get project_event_path(projects(:one), ingest_events(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Stacktrace")
        expect(response.body).to include(ingest_events(:one).message)
      end

      it "renders the Turbo detail frame when requested from the inbox" do
        get project_event_path(projects(:one), ingest_events(:one)), headers: { "Turbo-Frame" => "error_detail" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('<turbo-frame id="error_detail"')
        expect(response.body).to include("Context")
        expect(response.body).to include("Related logs")
        expect(response.body).to include('aria-current="page"')
        expect(response.body).to include('aria-selected="true"')
      end
    end

    context "when shared member" do
      before { sign_in users(:two) }

      it "returns success and event detail" do
        get project_event_path(projects(:one), ingest_events(:one))
        expect(response).to have_http_status(:success)
        expect(response.body).to include(ingest_events(:one).message)
      end
    end

    context "when viewing a CFML project error" do
      before { sign_in users(:two) }

      it "renders the CFML-focused exception view" do
        event = IngestEvent.create!(
          project: projects(:two),
          api_key: api_keys(:two),
          event_type: :error,
          level: "error",
          message: "Variable CUSTOMER is undefined.",
          fingerprint: "cfml-expression-customer",
          context: {
            exception: {
              type: "Expression",
              message: "Variable CUSTOMER is undefined.",
              detail: "The error occurred while evaluating the expression.",
              tagContext: [
                {
                  template: "/srv/www/app/orders/show.cfm",
                  line: 27,
                  type: "Expression",
                  codePrintPlain: "writeOutput(customer.name)"
                }
              ]
            },
            cgi: {
              script_name: "/orders/show.cfm",
              request_method: "GET",
              query_string: "id=42",
              remote_addr: "203.0.113.8",
              http_user_agent: "LuceeTest/1.0"
            }
          },
          occurred_at: Time.current
        )

        get project_event_path(projects(:two), event)
        expect(response).to have_http_status(:success)
        expect(response.body).to include("ColdFusion exception")
        expect(response.body).to include("Variable CUSTOMER is undefined.")
        expect(response.body).to include("/srv/www/app/orders/show.cfm")
        expect(response.body).to include("Template Frames")
      end
    end

    context "when viewing a Python project error" do
      before { sign_in users(:one) }

      it "renders the Python-focused exception view" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python API")
        api_key = create(:api_key, user: users(:one), project: project, name: "python")
        event = IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :error,
          level: "error",
          message: "ValueError: invalid checkout state",
          fingerprint: "python-valueerror-checkout",
          context: {
            exception: {
              class: "ValueError",
              qualified_class: "builtins.ValueError",
              message: "invalid checkout state",
              frames: [
                {
                  filename: "/srv/app/checkout.py",
                  lineno: 41,
                  name: "create_checkout",
                  line: "raise ValueError('invalid checkout state')",
                  locals: { "order_id" => "ord_123" }
                }
              ],
              cause: {
                class: "KeyError",
                message: "customer_id",
                frames: [
                  {
                    filename: "/srv/app/customer_lookup.py",
                    lineno: 12,
                    name: "fetch_customer",
                    line: "raise KeyError('customer_id')"
                  }
                ]
              },
              backtrace: [
                'File "/srv/app/checkout.py", line 41, in create_checkout'
              ]
            },
            framework: "fastapi",
            runtime: "python",
            python_version: "3.12.3",
            python_implementation: "CPython",
            platform: "macOS-14.0-arm64",
            hostname: "api-1",
            process_id: 4242,
            release: "api@2026.04.22",
            route: "/checkouts",
            request: {
              method: "POST",
              params: { "order_id" => "ord_123" },
              request_id: "req-python-1",
              url: "https://api.example.com/checkouts",
              client_ip: "203.0.113.8",
              query_string: "preview=true"
            }
          },
          occurred_at: Time.current
        )

        get project_event_path(project, event)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("ValueError")
        expect(response.body).to include("create_checkout")
        expect(response.body).to include("/srv/app/checkout.py")
        expect(response.body).to include("invalid checkout state")
        expect(response.body).to include("Runtime details")
        expect(response.body).to include("CPython")
        expect(response.body).to include("api@2026.04.22")
        expect(response.body).to include("Exception chain")
        expect(response.body).to include("KeyError")
        expect(response.body).to include("Frame locals")
        expect(response.body).to include('data-action="copy#copy"')
        expect(response.body).not_to include("onclick=")
      end
    end

    context "when viewing a Python project log event" do
      before { sign_in users(:one) }

      it "renders the Python logging-focused details view" do
        project = create(:project, user: users(:one), integration_kind: "python", name: "Python Worker")
        api_key = create(:api_key, user: users(:one), project: project, name: "python-logs")
        event = IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :log,
          level: "warning",
          message: "Inventory cache miss",
          context: {
            logger_name: "inventory.cache",
            logger: {
              name: "inventory.cache",
              module: "inventory.worker",
              pathname: "/srv/app/inventory/worker.py",
              filename: "worker.py",
              function: "refresh_cache",
              line_number: 88,
              process: 7021,
              thread: 19
            },
            log_record: {
              request_id: "req-log-1",
              trace_id: "trace-log-1",
              sku: "sku_42",
              warehouse: "east"
            },
            framework: "celery",
            runtime: "python",
            python_version: "3.12.3",
            hostname: "worker-2",
            process_id: 7021,
            release: "worker@2026.04.22",
            task_name: "inventory.refresh",
            task_id: "task-123",
            task_module: "inventory.tasks",
            request: {
              request_id: "req-log-1",
              url: "https://api.example.com/internal/inventory/refresh",
              method: "POST"
            }
          },
          occurred_at: Time.current
        )

        get project_event_path(project, event)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Python log event")
        expect(response.body).to include("Logger details")
        expect(response.body).to include("inventory.cache")
        expect(response.body).to include("refresh_cache")
        expect(response.body).to include("Runtime details")
        expect(response.body).to include("Execution details")
        expect(response.body).to include("inventory.tasks")
        expect(response.body).to include("Log record fields")
        expect(response.body).to include("sku_42")
        expect(response.body).to include(">Details<")
      end
    end

    context "when viewing a .NET project error" do
      before { sign_in users(:one) }

      it "renders the .NET-focused exception view" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "QuriaTime")
        api_key = create(:api_key, user: users(:one), project: project, name: "dotnet")
        event = IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :error,
          level: "error",
          message: "approval failed",
          fingerprint: "dotnet-approval-failed",
          context: {
            exception: {
              class: "InvalidOperationException",
              qualified_class: "System.InvalidOperationException",
              message: "approval failed",
              hresult: -2146233079,
              source: "QuriaTime.Web",
              target_site: "QuriaTime.Web.Services.ApprovalService.ApproveAsync",
              frames: [
                {
                  filename: "/src/QuriaTime.Web/Services/ApprovalService.cs",
                  lineno: 42,
                  name: "QuriaTime.Web.Services.ApprovalService.ApproveAsync",
                  raw: "at QuriaTime.Web.Services.ApprovalService.ApproveAsync in /src/QuriaTime.Web/Services/ApprovalService.cs:line 42"
                }
              ],
              inner_exception: {
                class: "ArgumentException",
                message: "missing manager"
              },
              data: {
                timesheet_id: "ts_123"
              }
            },
            framework: "aspnetcore",
            runtime: ".NET",
            dotnet_version: "8.0.4",
            framework_description: ".NET 8.0.4",
            os_description: "Darwin 23.0.0",
            machine_name: "quriatime-web-1",
            process_id: 8080,
            release: "quriatime@2026.04.30",
            request_id: "req-dotnet-1",
            trace_id: "trace-dotnet-1",
            route: "POST /approvals/{id}",
            request: {
              method: "POST",
              url: "https://quriatime.example.com/approvals/123?approval_id=123",
              query_string: "?approval_id=123",
              headers: {
                "User-Agent" => "DotNetTest/1.0"
              },
              route: {
                "controller" => "Approvals",
                "action" => "Review"
              },
              request_id: "req-dotnet-1"
            }
          },
          occurred_at: Time.current
        )

        get project_event_path(project, event)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("An unhandled exception occurred while processing the request.")
        expect(response.body).to include("Query")
        expect(response.body).to include("Cookies")
        expect(response.body).to include("Headers")
        expect(response.body).to include("Routing")
        expect(response.body).to include("InvalidOperationException")
        expect(response.body).to include("ApprovalService.ApproveAsync")
        expect(response.body).to include("/src/QuriaTime.Web/Services/ApprovalService.cs")
        expect(response.body).to include("approval_id")
        expect(response.body).to include("User-Agent")
        expect(response.body).to include("Runtime details")
        expect(response.body).to include(".NET 8.0.4")
        expect(response.body).to include("Exception chain")
        expect(response.body).to include("ArgumentException")
        expect(response.body).to include("Exception data")
        expect(response.body).to include("timesheet_id")
        expect(response.body).to include("trace-dotnet-1")
      end
    end

    context "when viewing a .NET project log event" do
      before { sign_in users(:one) }

      it "renders the .NET logging-focused details view" do
        project = create(:project, user: users(:one), integration_kind: "dotnet", name: "QuriaTime Worker")
        api_key = create(:api_key, user: users(:one), project: project, name: "dotnet-logs")
        event = IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :log,
          level: "warning",
          message: "Approval queue backlog rising",
          context: {
            logger_name: "QuriaTime.Web.Services.ApprovalService",
            logger: {
              event_id: 42,
              event_name: "ApprovalQueueBacklog",
              source_context: "QuriaTime.Web.Services.ApprovalService"
            },
            log_record: {
              queue: "approval-email",
              backlog: 17
            },
            framework: "aspnetcore",
            runtime: ".NET",
            dotnet_version: "8.0.4",
            machine_name: "worker-1",
            route: "BackgroundService NotificationOutboxWorker",
            status: 200,
            duration_ms: 87.4,
            request: {
              method: "POST",
              url: "https://quriatime.example.com/internal/approval-drain"
            }
          },
          occurred_at: Time.current
        )

        get project_event_path(project, event)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(".NET log event")
        expect(response.body).to include("Logger details")
        expect(response.body).to include("ApprovalQueueBacklog")
        expect(response.body).to include("Runtime details")
        expect(response.body).to include("Execution details")
        expect(response.body).to include("Log record fields")
        expect(response.body).to include("approval-email")
        expect(response.body).to include(">Details<")
      end
    end

    context "when viewing a JavaScript project error" do
      before { sign_in users(:one) }

      it "renders the JavaScript-focused exception view" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Web App")
        api_key = create(:api_key, user: users(:one), project: project, name: "javascript")
        event = IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :error,
          level: "error",
          message: "TypeError: Cannot read properties of undefined",
          fingerprint: "javascript-typeerror-checkout",
          context: {
            exception: {
              class: "TypeError",
              message: "Cannot read properties of undefined",
              frames: [
                {
                  filename: "https://app.example.com/assets/app.min.js",
                  lineno: 2,
                  colno: 1450,
                  name: "renderCheckout"
                },
                {
                  filename: "https://app.example.com/assets/app.min.js",
                  lineno: 9,
                  colno: 321,
                  name: "onSubmit"
                }
              ],
              backtrace: [
                "at renderCheckout (https://app.example.com/assets/app.min.js:2:1450)",
                "at onSubmit (https://app.example.com/assets/app.min.js:9:321)"
              ],
              stack: <<~STACK,
                TypeError: Cannot read properties of undefined
                    at renderCheckout (https://app.example.com/assets/app.min.js:2:1450)
                    at onSubmit (https://app.example.com/assets/app.min.js:9:321)
              STACK
              cause: {
                class: "Error",
                message: "checkout state missing",
                frames: [
                  {
                    filename: "https://app.example.com/src/lib/checkout.ts",
                    lineno: 27,
                    colno: 14,
                    name: "validateCheckout"
                  }
                ]
              }
            },
            browser: "Chrome 135",
            os: "macOS",
            route: "/checkout",
            release: "web@2026.04.22",
            user_agent: "Mozilla/5.0",
            breadcrumbs: [
              { category: "ui.click", message: "Clicked checkout button" }
            ]
          },
          occurred_at: Time.current
        )

        get project_event_path(project, event)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("JavaScript")
        expect(response.body).to include("renderCheckout")
        expect(response.body).to include("Chrome 135")
        expect(response.body).to include("Breadcrumbs")
        expect(response.body).to include("Source map hint")
        expect(response.body).to include("Exception chain")
        expect(response.body).to include("checkout state missing")
      end
    end

    context "when viewing a JavaScript project log event" do
      before { sign_in users(:one) }

      it "renders the JavaScript logging-focused details view" do
        project = create(:project, user: users(:one), integration_kind: "javascript", name: "Web Worker")
        api_key = create(:api_key, user: users(:one), project: project, name: "javascript-logs")
        event = IngestEvent.create!(
          project: project,
          api_key: api_key,
          event_type: :log,
          level: "warning",
          message: "Queue backlog rising",
          context: {
            logger_name: "console",
            logger: {
              name: "console",
              method: "warn",
              filename: "worker.js",
              function: "flushQueue"
            },
            log_record: {
              arguments: [ "Queue backlog rising", { "queue" => "emails" } ],
              original_method: "warn"
            },
            runtime: "node",
            route: "/jobs/email-drain",
            release: "web@2026.04.22",
            url: "https://app.example.com/jobs/email-drain"
          },
          occurred_at: Time.current
        )

        get project_event_path(project, event)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("JavaScript log event")
        expect(response.body).to include("Logger details")
        expect(response.body).to include("console")
        expect(response.body).to include("warn")
        expect(response.body).to include("Runtime details")
        expect(response.body).to include("Log record fields")
        expect(response.body).to include("Queue backlog rising")
        expect(response.body).to include(">Details<")
      end
    end

    context "when non-member" do
      before { sign_in users(:one) }

      it "returns 404" do
        get project_event_path(projects(:two), ingest_events(:two))
        expect(response).to have_http_status(:not_found)
      end
    end

    it "renders structured request context when present" do
      sign_in users(:one)
      event = IngestEvent.create!(
        project: projects(:one),
        api_key: api_keys(:one),
        event_type: :error,
        level: "error",
        message: "NoMethodError: undefined method",
        fingerprint: "nomethoderror-structured-context",
        context: {
          clientIp: "66.241.125.180",
          headers: { "Referer" => "https://example.com/page", "Version" => "HTTP/1.1" },
          httpMethod: "GET",
          params: { "page" => "6", "controller" => "blogs", "action" => "show", "id" => "slug" },
          requestId: "d1585398-6817-41cd-bffb-0de457eea5b6",
          url: "https://example.com/content/slug"
        },
        occurred_at: Time.current
      )
      get project_event_path(projects(:one), event)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("clientIp")
      expect(response.body).to include("66.241.125.180")
    end
  end
end
