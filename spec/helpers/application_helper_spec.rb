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
end
