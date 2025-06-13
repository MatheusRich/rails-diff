require "fileutils"
require "tmpdir"

class GitRepo
  attr_reader :remote_repo, :commits

  # Initializes and creates a bare remote repo and a working repo with main branch
  def initialize
    @remote_dir = Dir.mktmpdir
    @remote_repo = File.join(@remote_dir, "origin.git")
    Dir.chdir(@remote_dir) { `git init --bare origin.git > /dev/null 2>&1` }

    @commits = []
    @work_dir = Dir.mktmpdir
    Dir.chdir(@work_dir) do
      `git clone #{@remote_repo} . > /dev/null 2>&1`
      `git checkout -b main > /dev/null 2>&1`
      # Always create the 'railties' directory for test convenience
      FileUtils.mkdir_p("railties")
      File.write("railties/.keep", "keep")
      `git add railties > /dev/null 2>&1`
      `git commit -m "add railties dir" > /dev/null 2>&1`
      @commits << `git rev-parse HEAD`.strip
      `git push origin main > /dev/null 2>&1`
    end
  end

  # Adds a commit with the given message and pushes to remote
  def add_commit(message)
    Dir.chdir(@work_dir) do
      filename = "file#{@commits.size}.txt"
      File.write(filename, message)
      `git add . > /dev/null 2>&1`
      `git commit -m "#{message}" > /dev/null 2>&1`
      sha = `git rev-parse HEAD`.strip
      @commits << sha
      `git push origin main > /dev/null 2>&1`
    end

    @commits.last
  end

  def clone_at_commit(commit_sha, dest_path)
    `git clone #{@remote_repo} #{dest_path} > /dev/null 2>&1`
    Dir.chdir(dest_path) { `git checkout #{commit_sha} > /dev/null 2>&1` }
  end

  def cleanup
    FileUtils.rm_rf(@remote_dir)
    FileUtils.rm_rf(@work_dir)
  end
end
