# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#json_ld" do
    it "escapes unsafe characters in JSON-LD output" do
      rendered = helper.json_ld({ name: "</script><script>alert(1)</script>" })

      expect(rendered).to include("\\u003c/script\\u003e")
      expect(rendered).not_to include("</script>")
    end
  end

  describe "#docs_site_url" do
    it "returns the Cloudflare-hosted docs URL for the requested section" do
      expect(helper.docs_site_url).to eq("https://docs.logister.org/")
      expect(helper.docs_site_url(:http_api)).to eq("https://docs.logister.org/http-api/")
      expect(helper.docs_site_url(:cfml_integration)).to eq("https://docs.logister.org/integrations/cfml/")
      expect(helper.docs_site_url(:javascript_integration)).to eq("https://docs.logister.org/integrations/javascript/")
      expect(helper.docs_site_url(:python_integration)).to eq("https://docs.logister.org/integrations/python/")
      expect(helper.docs_site_url(:dotnet_integration)).to eq("https://docs.logister.org/integrations/dotnet/")
    end
  end

  describe "#parse_backtrace_frames" do
    it "parses structured CFML tagContext frames" do
      frames = helper.parse_backtrace_frames([
        {
          "template" => "/var/www/app/views/orders/show.cfm",
          "line" => 42,
          "type" => "Expression",
          "codePrintPlain" => "customer = order.getCustomer()"
        }
      ])

      expect(frames.size).to eq(1)
      expect(frames.first[:file]).to eq("/var/www/app/views/orders/show.cfm")
      expect(frames.first[:line_number]).to eq(42)
      expect(frames.first[:method_name]).to eq("Expression")
      expect(frames.first[:code_context]).to include("order.getCustomer")
    end

    it "parses structured Python traceback frames and raw traceback lines" do
      frames = helper.parse_backtrace_frames([
        {
          "filename" => "/srv/app/orders.py",
          "lineno" => 27,
          "name" => "create_order",
          "line" => "raise ValueError('bad order')"
        },
        'File "/srv/app/views.py", line 11, in dispatch'
      ])

      expect(frames.size).to eq(2)
      expect(frames.first[:file]).to eq("/srv/app/orders.py")
      expect(frames.first[:line_number]).to eq(27)
      expect(frames.first[:method_name]).to eq("create_order")
      expect(frames.first[:code_context]).to eq("raise ValueError('bad order')")
      expect(frames.second[:file]).to eq("/srv/app/views.py")
      expect(frames.second[:line_number]).to eq(11)
      expect(frames.second[:method_name]).to eq("dispatch")
    end

    it "parses JavaScript stack trace lines from Chrome and Firefox formats" do
      frames = helper.parse_backtrace_frames([
        "at renderCheckout (https://app.example.com/assets/app.min.js:2:1450)",
        "handleClick@https://app.example.com/assets/chunk.js:88:19"
      ])

      expect(frames.size).to eq(2)
      expect(frames.first[:file]).to eq("https://app.example.com/assets/app.min.js")
      expect(frames.first[:line_number]).to eq(2)
      expect(frames.first[:column_number]).to eq(1450)
      expect(frames.first[:method_name]).to eq("renderCheckout")
      expect(frames.second[:file]).to eq("https://app.example.com/assets/chunk.js")
      expect(frames.second[:line_number]).to eq(88)
      expect(frames.second[:column_number]).to eq(19)
      expect(frames.second[:method_name]).to eq("handleClick")
    end
  end

  describe "#cfml_exception_summary" do
    it "prefers CFML exception fields" do
      summary = helper.cfml_exception_summary(
        {
          "type" => "Expression",
          "message" => "Element CUSTOMER is undefined in ORDER.",
          "detail" => "The error occurred while processing the template.",
          "errorCode" => "expression"
        },
        "fallback message"
      )

      expect(summary[:class_name]).to eq("Expression")
      expect(summary[:message]).to eq("Element CUSTOMER is undefined in ORDER.")
      expect(summary[:detail]).to eq("The error occurred while processing the template.")
      expect(summary[:error_code]).to eq("expression")
    end
  end

  describe "#python_exception_chain" do
    it "collects nested cause and context exceptions" do
      chain = helper.python_exception_chain(
        {
          "class" => "RuntimeError",
          "message" => "checkout failed",
          "cause" => {
            "class" => "ValueError",
            "message" => "invalid order",
            "frames" => [ { "filename" => "/srv/app/orders.py", "lineno" => 12, "name" => "load_order" } ]
          },
          "context" => {
            "class" => "KeyError",
            "message" => "customer_id"
          }
        }
      )

      expect(chain.map { |entry| entry[:label] }).to eq(%w[cause context])
      expect(chain.map { |entry| entry[:class_name] }).to eq(%w[ValueError KeyError])
      expect(chain.first[:frames].first[:method_name]).to eq("load_order")
    end
  end

  describe "#python_logger_details" do
    it "extracts logger metadata from event context" do
      event = Struct.new(:context).new(
        {
          "logger_name" => "inventory.cache",
          "logger" => {
            "function" => "refresh_cache",
            "filename" => "worker.py",
            "line_number" => 88
          }
        }
      )

      details = helper.python_logger_details(event)

      expect(details[:logger_name]).to eq("inventory.cache")
      expect(details[:function]).to eq("refresh_cache")
      expect(details[:filename]).to eq("worker.py")
      expect(details[:line_number]).to eq(88)
    end
  end

  describe "#python_activity_summary" do
    it "builds a compact logger and task summary" do
      event = Struct.new(:context).new(
        {
          "logger_name" => "inventory.cache",
          "logger" => {
            "function" => "refresh_cache",
            "filename" => "worker.py"
          },
          "task_name" => "inventory.refresh"
        }
      )

      expect(helper.python_activity_summary(event)).to eq("inventory.cache · refresh_cache() in worker.py · task inventory.refresh")
    end
  end

  describe "#event_exception_data" do
    it "extracts exception data from event context" do
      event = Struct.new(:context).new({
        "exception" => {
          "class" => "RuntimeError",
          "message" => "boom"
        }
      })

      expect(helper.event_exception_data(event)).to eq({
        "class" => "RuntimeError",
        "message" => "boom"
      })
    end
  end

  describe "#event_backtrace" do
    it "returns the structured backtrace from exception data" do
      exception_data = {
        "backtrace" => [
          'File "/srv/app/service.py", line 12, in call'
        ]
      }

      expect(helper.event_backtrace(exception_data)).to eq([
        'File "/srv/app/service.py", line 12, in call'
      ])
    end
  end

  describe "#event_local_variables" do
    it "prefers locals and local_variables hashes" do
      expect(helper.event_local_variables({ "locals" => { "order_id" => "ord_123" } })).to eq({ "order_id" => "ord_123" })
      expect(helper.event_local_variables({ "local_variables" => { "user_id" => "usr_123" } })).to eq({ "user_id" => "usr_123" })
    end
  end

  describe "#event_instance_variables" do
    it "extracts instance variables as a normalized hash" do
      expect(helper.event_instance_variables({ "instance_variables" => { "@order" => "ord_123" } })).to eq({ "@order" => "ord_123" })
      expect(helper.event_instance_variables(nil)).to eq({})
    end
  end

  describe "#event_stacktrace_tab_label" do
    it "uses Details for Python, JavaScript, and .NET log events" do
      python_project = Project.new(integration_kind: "python")
      javascript_project = Project.new(integration_kind: "javascript")
      dotnet_project = Project.new(integration_kind: "dotnet")
      log_event = Struct.new(:log?).new(true)

      expect(helper.event_stacktrace_tab_label(python_project, log_event)).to eq("Details")
      expect(helper.event_stacktrace_tab_label(javascript_project, log_event)).to eq("Details")
      expect(helper.event_stacktrace_tab_label(dotnet_project, log_event)).to eq("Details")
    end

    it "uses Stacktrace for non-log events" do
      ruby_project = Project.new(integration_kind: "ruby")
      error_event = Struct.new(:log?).new(false)

      expect(helper.event_stacktrace_tab_label(ruby_project, error_event)).to eq("Stacktrace")
    end
  end

  describe "#event_stacktrace_partial" do
    it "resolves the language-specific partial path" do
      log_event = Struct.new(:log?).new(true)
      error_event = Struct.new(:log?).new(false)

      expect(helper.event_stacktrace_partial(Project.new(integration_kind: "python"), log_event)).to eq("project_events/python_log_event")
      expect(helper.event_stacktrace_partial(Project.new(integration_kind: "javascript"), log_event)).to eq("project_events/javascript_log_event")
      expect(helper.event_stacktrace_partial(Project.new(integration_kind: "dotnet"), log_event)).to eq("project_events/dotnet_log_event")
      expect(helper.event_stacktrace_partial(Project.new(integration_kind: "cfml"), error_event)).to eq("project_events/cfml_stacktrace")
      expect(helper.event_stacktrace_partial(Project.new(integration_kind: "dotnet"), error_event)).to eq("project_events/dotnet_stacktrace")
      expect(helper.event_stacktrace_partial(Project.new(integration_kind: "ruby"), error_event)).to eq("project_events/ruby_stacktrace")
    end
  end

  describe "#javascript_exception_chain" do
    it "collects nested JavaScript causes and context values" do
      chain = helper.javascript_exception_chain(
        {
          "class" => "TypeError",
          "message" => "render failed",
          "cause" => {
            "class" => "Error",
            "message" => "missing state",
            "frames" => [ { "filename" => "/app/src/state.ts", "lineno" => 18, "name" => "readState" } ]
          },
          "context" => {
            "values" => [
              { "class" => "NetworkError", "message" => "upstream timeout" }
            ]
          }
        }
      )

      expect(chain.map { |entry| entry[:label] }).to eq(%w[cause context])
      expect(chain.map { |entry| entry[:class_name] }).to eq(%w[Error NetworkError])
      expect(chain.first[:frames].first[:method_name]).to eq("readState")
    end
  end

  describe "#javascript_logger_details" do
    it "extracts logger metadata from JavaScript log events" do
      event = Struct.new(:context).new(
        {
          "logger_name" => "console",
          "logger" => {
            "method" => "warn",
            "function" => "flushQueue",
            "filename" => "worker.js"
          }
        }
      )

      details = helper.javascript_logger_details(event)

      expect(details[:logger_name]).to eq("console")
      expect(details[:method]).to eq("warn")
      expect(details[:function]).to eq("flushQueue")
      expect(details[:filename]).to eq("worker.js")
    end
  end

  describe "#javascript_activity_summary" do
    it "builds a compact logger and route summary" do
      event = Struct.new(:context).new(
        {
          "logger_name" => "console",
          "logger" => {
            "method" => "warn",
            "function" => "flushQueue",
            "filename" => "worker.js"
          },
          "route" => "/jobs/email-drain"
        }
      )

      expect(helper.javascript_activity_summary(event)).to eq("console · warn · flushQueue() in worker.js · /jobs/email-drain")
    end
  end

  describe "#dotnet_activity_summary" do
    it "builds a compact logger and route summary" do
      event = Struct.new(:context).new(
        {
          "logger_name" => "QuriaTime.Web.Services.ApprovalService",
          "logger" => {
            "event_name" => "ApprovalFailed"
          },
          "route" => "POST /approvals/{id}",
          "status" => 500,
          "framework" => "aspnetcore"
        }
      )

      expect(helper.dotnet_activity_summary(event)).to eq("QuriaTime.Web.Services.ApprovalService · ApprovalFailed · POST /approvals/{id} · status 500 · aspnetcore")
    end
  end
end
