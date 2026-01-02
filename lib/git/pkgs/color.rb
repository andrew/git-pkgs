# frozen_string_literal: true

module Git
  module Pkgs
    module Color
      CODES = {
        red: 31,
        green: 32,
        yellow: 33,
        blue: 34,
        magenta: 35,
        cyan: 36,
        bold: 1,
        dim: 2
      }.freeze

      def self.enabled?
        return @enabled if defined?(@enabled)

        @enabled = determine_color_support
      end

      def self.enabled=(value)
        @enabled = value
      end

      def self.determine_color_support
        return false unless $stdout.respond_to?(:tty?) && $stdout.tty?
        return false if ENV["NO_COLOR"] && !ENV["NO_COLOR"].empty?
        return false if ENV["TERM"] == "dumb"

        true
      end

      def self.colorize(text, *codes)
        return text unless enabled?

        code_str = codes.map { |c| CODES[c] || c }.join(";")
        "\e[#{code_str}m#{text}\e[0m"
      end

      def self.red(text)     = colorize(text, :red)
      def self.green(text)   = colorize(text, :green)
      def self.yellow(text)  = colorize(text, :yellow)
      def self.blue(text)    = colorize(text, :blue)
      def self.cyan(text)    = colorize(text, :cyan)
      def self.bold(text)    = colorize(text, :bold)
      def self.dim(text)     = colorize(text, :dim)
    end
  end
end
