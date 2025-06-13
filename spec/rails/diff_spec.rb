# frozen_string_literal: true

RSpec.describe Rails::Diff do
  it "has a version number" do
    expect(Rails::Diff::VERSION).not_to be nil
  end
  
  describe ".generated" do
    before do
      allow(Rails::Diff).to receive(:system!).and_return(true)
      allow(Rails::Diff).to receive(:ensure_template_app_exists)
      allow(Rails::Diff).to receive(:install_app_dependencies)
      allow(Rails::Diff).to receive(:generated_files).and_return(["file1.rb", "file2.rb"])
      allow(Rails::Diff).to receive(:diff_with_header).and_return("file1.rb diff:\n===\nDiff content")
    end

    it "returns the diff for generated files" do
      result = Rails::Diff.generated("model", "User", no_cache: true)
      expect(result).to include("file1.rb diff:")
    end
  end

  describe Rails::Diff::CLI do
    describe "#generated" do
      before do
        allow(Rails::Diff).to receive(:system!).and_return(true)
        allow(Rails::Diff).to receive(:generated).and_return("file1.rb diff:\n===\nDiff content")
      end

      it "runs without error" do
        cli = Rails::Diff::CLI.new
        expect { cli.generated("model", "User") }.not_to raise_error
      end
    end
  end
end