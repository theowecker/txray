# frozen_string_literal: true

module Txray
  class Railtie < ::Rails::Railtie
    config.txray = ActiveSupport::OrderedOptions.new

    rake_tasks { load File.expand_path("tasks.rake", __dir__) }

    initializer "txray.runtime" do |app|
      settings = Config.load.runtime.merge(app.config.txray.to_h.transform_keys(&:to_s))
      next unless settings["enabled"]

      ActiveSupport.on_load(:active_record) do
        Txray::Runtime.install(
          threshold_ms: settings["threshold_ms"],
          on_violation: settings["on_violation"],
          guard_http: settings["guard_http"],
          guard_jobs: settings["guard_jobs"],
          guard_mail: settings["guard_mail"],
          log_path: settings["log_path"],
          ignore: settings["ignore"]
        )
      end
    end
  end
end
