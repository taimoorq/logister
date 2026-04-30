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
end
