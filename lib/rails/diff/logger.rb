module Rails
  module Diff
    module Logger
      extend self

      def info(message)
        puts "\e[1;34minfo:\e[0m\t#{message}"
      end

      def debug(message)
        return unless ENV["DEBUG"]

        puts "\e[1;33mdebug:\e[0m\t#{message}"
      end

      def error(label, message)
        warn "\e[1;31m#{label}\e[0m #{message}"
      end
    end
  end
end
