# frozen_string_literal: true

require "open3"

module Rails
  module Diff
    module Shell
      extend self

      def run!(*cmd, logger:, abort: true)
        _, stderr, status = Open3.capture3(*cmd)
        logger.debug(cmd.join(" "))
        if status.success?
          true
        elsif abort
          logger.error("Command failed:", cmd.join(" "))
          abort stderr
        else
          false
        end
      end
    end
  end
end
