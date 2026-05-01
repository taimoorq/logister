# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectEvents::DotnetEventPresenter do
  describe "#frames" do
    it "parses structured frames and .NET stack trace lines" do
      presenter = described_class.new(nil, {
        "frames" => [
          {
            "filename" => "/src/QuriaTime.Web/Services/ApprovalService.cs",
            "lineno" => 42,
            "name" => "QuriaTime.Web.Services.ApprovalService.ApproveAsync"
          }
        ]
      })

      expect(presenter.frames.first[:file]).to eq("/src/QuriaTime.Web/Services/ApprovalService.cs")
      expect(presenter.frames.first[:method_name]).to eq("QuriaTime.Web.Services.ApprovalService.ApproveAsync")

      stack_presenter = described_class.new(nil, {
        "stack" => "   at QuriaTime.Web.Controllers.ApprovalsController.Review() in /src/QuriaTime.Web/Controllers/ApprovalsController.cs:line 31"
      })

      expect(stack_presenter.frames.first[:file]).to eq("/src/QuriaTime.Web/Controllers/ApprovalsController.cs")
      expect(stack_presenter.frames.first[:line_number]).to eq(31)
    end

    it "formats structured frames as familiar .NET stack lines" do
      presenter = described_class.new(nil, {
        "frames" => [
          {
            "filename" => "/src/QuriaTime.Web/Controllers/UsersController.cs",
            "lineno" => 12,
            "name" => "QuriaTime.Web.Controllers.Admin.UsersController.Index"
          }
        ]
      })

      expect(presenter.stack_lines).to eq([
        "at QuriaTime.Web.Controllers.Admin.UsersController.Index in /src/QuriaTime.Web/Controllers/UsersController.cs:line 12"
      ])
    end
  end

  describe "#exception_chain" do
    it "collects inner exceptions and aggregate children" do
      chain = described_class.new(nil, {
        "class" => "AggregateException",
        "message" => "One or more errors occurred.",
        "inner_exception" => {
          "class" => "InvalidOperationException",
          "message" => "approval failed"
        },
        "inner_exceptions" => [
          {
            "class" => "TimeoutException",
            "message" => "mail timed out"
          }
        ]
      }).exception_chain

      expect(chain.map { |entry| entry[:label] }).to eq(%w[inner aggregate])
      expect(chain.map { |entry| entry[:class_name] }).to eq(%w[InvalidOperationException TimeoutException])
    end
  end

  describe "#endpoint_matches" do
    it "extracts ASP.NET Core ambiguous endpoint matches from the exception message" do
      presenter = described_class.new(nil, {
        "class" => "AmbiguousMatchException",
        "message" => <<~MESSAGE
          The request matched multiple endpoints. Matches:

          QuriaTime.Web.Controllers.Admin.UsersController.Index (QuriaTime.Web)
          QuriaTime.Web.Controllers.Admin.UsersController.Index (QuriaTime.Web)
        MESSAGE
      })

      expect(presenter.developer_exception_title).to eq(
        "AmbiguousMatchException: The request matched multiple endpoints. Matches:"
      )
      expect(presenter.endpoint_matches).to eq([
        "QuriaTime.Web.Controllers.Admin.UsersController.Index (QuriaTime.Web)",
        "QuriaTime.Web.Controllers.Admin.UsersController.Index (QuriaTime.Web)"
      ])
    end
  end

  describe "request detail sections" do
    it "normalizes query, cookies, headers, and routing details for the developer page layout" do
      presenter = described_class.new({
        "request" => {
          "query_string" => "?page=2&status=open",
          "headers" => {
            "User-Agent" => "DotNetTest/1.0",
            "Cookie" => "session=abc"
          },
          "route" => {
            "controller" => "Users",
            "action" => "Index"
          },
          "path" => "/admin/users",
          "method" => "GET",
          "url" => "https://quriatime.example.com/admin/users?page=2&status=open"
        },
        "route" => "QuriaTime.Web.Controllers.Admin.UsersController.Index",
        "trace_id" => "trace-dotnet-1"
      })

      expect(presenter.query_parameters).to include("page" => "2", "status" => "open")
      expect(presenter.request_headers).to include("User-Agent" => "DotNetTest/1.0")
      expect(presenter.request_cookies).to include("session" => "abc")
      expect(presenter.routing_details).to include(
        route: "QuriaTime.Web.Controllers.Admin.UsersController.Index",
        trace_id: "trace-dotnet-1"
      )
      expect(presenter.routing_details[:route_values]).to include("controller" => "Users")
    end
  end
end
