require "rspec"
require "rails/diff/cli"

RSpec.describe Rails::Diff::CLI do
  let(:cli) { described_class.new }
  let(:mock_diff) { "Mocked diff output" }

  before do
    allow(Rails::Diff).to receive(:file).and_return(mock_diff)
  end

  describe "#file" do
    context "when no files are provided" do
      it "aborts with an error message" do
        expect { cli.file }.to raise_error(SystemExit, "Please provide at least one file to compare")
      end
    end

    context "when files are provided" do
      it "outputs the diff if differences exist" do
        expect { cli.file("file1.rb", "file2.rb") }.to output("#{mock_diff}\n").to_stdout
      end

      it "aborts if differences exist and fail option is set" do
        cli.options = { fail: true }
        expect { cli.file("file1.rb", "file2.rb") }.to raise_error(SystemExit, mock_diff)
      end
    end
  end

  describe "#dotfiles" do
    let(:mock_dotfiles) { [".env", ".gitignore"] }

    before do
      allow(Dir).to receive(:glob).with("**/.*").and_return(mock_dotfiles)
      allow(mock_dotfiles).to receive(:reject).and_return(mock_dotfiles)
    end

    context "when no dotfiles are found" do
      before do
        allow(Dir).to receive(:glob).with("**/.*").and_return([])
      end

      it "does not output anything" do
        expect { cli.dotfiles }.to_not output.to_stdout
      end
    end

    context "when dotfiles are found and differences exist" do
      before do
        allow(Rails::Diff).to receive(:file).and_return(mock_diff)
      end

      it "outputs the diff" do
        expect { cli.dotfiles }.to output("#{mock_diff}\n").to_stdout
      end
    end
  end
end