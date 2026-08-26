# frozen_string_literal: true

require "rails/generators/base"

module Txray
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Writes .txray.yml and explains how to turn the runtime guard on."

      def create_config
        copy_file "txray.yml", ".txray.yml"
      end

      def explain
        say ""
        say "Scan the application:", :green
        say "  bundle exec txray"
        say ""
        say "To watch transactions live, set runtime.enabled to true in .txray.yml,", :green
        say "make sure the Gemfile does not say require: false, restart, then run:"
        say "  bundle exec txray watch"
        say ""
      end
    end
  end
end
