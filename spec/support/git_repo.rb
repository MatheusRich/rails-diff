require "fileutils"
require "tmpdir"

class GitRepo
  attr_reader :remote_repo, :commits

  # Initializes and creates a bare remote repo and a working repo with main branch
  def initialize
    @remote_dir = Dir.mktmpdir
    @remote_repo = File.join(@remote_dir, "origin.git")
    Dir.chdir(@remote_dir) { `git init --bare --initial-branch=main origin.git > /dev/null 2>&1` }

    @commits = []
    @work_dir = Dir.mktmpdir
    Dir.chdir(@work_dir) do
      `git clone #{@remote_repo} . > /dev/null 2>&1`
      `git checkout -b main > /dev/null 2>&1`
      FileUtils.mkdir_p("railties")
      File.write("railties/README", "keep")
      `git add railties > /dev/null 2>&1`

      `git config user.email 'test@example.com'`
      `git config user.name 'Test User'`

      commit_result = `git commit -m "add railties dir" 2>&1`
      raise "Initial commit failed: #{commit_result}" unless $?.success?
      @commits << `git rev-parse HEAD`.strip
      `git push -u origin main > /dev/null 2>&1`
    end
  end

  def add_commit(message)
    Dir.chdir(@work_dir) do
      `git commit --allow-empty -n -m "#{message}" > /dev/null 2>&1`
      sha = `git rev-parse HEAD`.strip
      @commits << sha
      `git push origin main > /dev/null 2>&1`
      `git fetch origin main > /dev/null 2>&1`
    end

    @commits.last
  end

  def clone_at_commit(commit_sha, dest_path)
    `git clone #{@remote_repo} #{dest_path} > /dev/null 2>&1`
    Dir.chdir(dest_path) do
      `git checkout #{commit_sha} > /dev/null 2>&1`
      `git fetch origin main > /dev/null 2>&1`
    end
  end

  def cleanup
    Dir.chdir(@work_dir) do
      `git reset --hard main > /dev/null 2>&1`
      `git clean -fdx > /dev/null 2>&1`
    end
  end
end
