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
end
