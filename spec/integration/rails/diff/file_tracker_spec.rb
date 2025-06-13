# frozen_string_literal: true

require 'rails/diff/file_tracker'

RSpec.describe FileTracker do
  context 'integration tests' do
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.remove_entry(temp_dir)
    end

    it 'tracks newly created files' do
      FileUtils.touch("#{temp_dir}/file1.rb")
      file_tracker = FileTracker.new

      new_files = file_tracker.track_new_files(temp_dir, []) do
        FileUtils.touch("#{temp_dir}/file2.rb")
        FileUtils.touch("#{temp_dir}/file3.rb")
      end

      expect(new_files).to contain_exactly("#{temp_dir}/file2.rb", "#{temp_dir}/file3.rb")
    end

    it 'excludes skipped files' do
      FileUtils.touch("#{temp_dir}/file1.rb")
      file_tracker = FileTracker.new

      new_files = file_tracker.track_new_files(temp_dir, ['file2.rb']) do
        FileUtils.touch("#{temp_dir}/file2.rb")
        FileUtils.touch("#{temp_dir}/file3.rb")
      end

      expect(new_files).to contain_exactly("#{temp_dir}/file3.rb")
    end

    it 'handles files with --only option' do
      FileUtils.touch("#{temp_dir}/file1.rb")
      file_tracker = FileTracker.new
      new_files = file_tracker.track_new_files(temp_dir, [], ['file2.rb']) do
        FileUtils.touch("#{temp_dir}/file2.rb")
        FileUtils.touch("#{temp_dir}/file3.rb")
      end
      expect(new_files).to contain_exactly("#{temp_dir}/file2.rb")
    end

    it 'ignores files in special directories' do
      FileUtils.mkdir_p("#{temp_dir}/.git")
      FileUtils.mkdir_p("#{temp_dir}/tmp")
      FileUtils.mkdir_p("#{temp_dir}/log")
      FileUtils.touch("#{temp_dir}/file1.rb")
      file_tracker = FileTracker.new

      new_files = file_tracker.track_new_files(temp_dir, []) do
        FileUtils.touch("#{temp_dir}/.git/config")
        FileUtils.touch("#{temp_dir}/tmp/cache")
        FileUtils.touch("#{temp_dir}/log/development.log")
        FileUtils.touch("#{temp_dir}/file2.rb")
      end

      expect(new_files).to contain_exactly("#{temp_dir}/file2.rb")
    end

    it 'handles nested directories' do
      FileUtils.touch("#{temp_dir}/file1.rb")
      file_tracker = FileTracker.new

      new_files = file_tracker.track_new_files(temp_dir, []) do
        FileUtils.mkdir_p("#{temp_dir}/nested/dir")
        FileUtils.touch("#{temp_dir}/nested/file2.rb")
        FileUtils.touch("#{temp_dir}/nested/dir/file3.rb")
      end

      expect(new_files).to contain_exactly("#{temp_dir}/nested/file2.rb", "#{temp_dir}/nested/dir/file3.rb")
    end
  end
end
