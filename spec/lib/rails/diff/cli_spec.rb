# frozen_string_literal: true

# require "spec_helper"

RSpec.describe Rails::Diff::CLI do
  describe "#file" do
    context "when --fail-on-diff is not specified" do
      it "exits successfully" do
        allow(Rails::Diff).to receive(:file).with("some_file.rb", kind_of(Hash)).and_return("diff output")

        expect {
          described_class.start(["file", "some_file.rb"])
        }.not_to raise_error
      end
    end

    context "when --fail-on-diff is specified" do
      it "exits with an error code" do
        allow(Rails::Diff).to receive(:file).with("some_file.rb", kind_of(Hash)).and_return("diff output")

        expect {
          described_class.start(["file", "some_file.rb", "--fail-on-diff"])
        }.to raise_error(SystemExit)
      end
    end
  end
end
