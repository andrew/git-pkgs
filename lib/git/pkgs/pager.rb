# frozen_string_literal: true

require "stringio"

module Git
  module Pkgs
    module Pager
      # Returns the pager command following git's precedence:
      # 1. GIT_PAGER environment variable
      # 2. core.pager git config
      # 3. PAGER environment variable
      # 4. less as fallback
      def git_pager
        return ENV["GIT_PAGER"] if ENV["GIT_PAGER"] && !ENV["GIT_PAGER"].empty?

        config_pager = `git config --get core.pager`.chomp
        return config_pager unless config_pager.empty?

        return ENV["PAGER"] if ENV["PAGER"] && !ENV["PAGER"].empty?

        "less -FRSX"
      end

      # Returns true if paging is disabled (pager set to empty string or 'cat')
      def pager_disabled?
        pager = git_pager
        pager.empty? || pager == "cat"
      end

      # Captures output from a block and sends it through the pager.
      # Falls back to direct output if:
      # - stdout is not a TTY
      # - pager is disabled
      # - pager command fails
      def paginate
        if !$stdout.tty? || pager_disabled? || paging_disabled?
          yield
          return
        end

        output = StringIO.new
        old_stdout = $stdout
        $stdout = output

        begin
          yield
        ensure
          $stdout = old_stdout
        end

        content = output.string
        return if content.empty?

        IO.popen(git_pager, "w") { |io| io.write(content) }
      rescue Errno::EPIPE
        # User quit pager early
      rescue Errno::ENOENT
        # Pager command not found, fall back to direct output
        print content
      end

      # Check if paging was disabled via --no-pager option
      def paging_disabled?
        defined?(@options) && @options.is_a?(Hash) && @options[:no_pager]
      end
    end
  end
end
