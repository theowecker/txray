# frozen_string_literal: true

namespace :txray do
  desc "Scan the application for transactions that hold the database open"
  task :scan do
    require "txray"
    exit Txray::CLI.start(ENV.fetch("TXRAY_ARGS", "").split)
  end
end
