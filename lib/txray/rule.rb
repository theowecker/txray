# frozen_string_literal: true

module Txray
  Rule = Struct.new(:id, :category, :severity, :message, :remedy, keyword_init: true)

  module Rules
    def self.all = @all ||= {}

    def self.register(id:, category:, severity:, message:, remedy:)
      all[id] = Rule.new(id: id, category: category, severity: severity, message: message, remedy: remedy)
    end

    def self.[](id) = all.fetch(id)
    def self.ids = all.keys

    register(
      id: "http-in-transaction",
      category: :transaction,
      severity: :high,
      message: "HTTP request `%{snippet}` runs inside %{scope}",
      remedy: "Move the request outside the transaction, or enqueue it from an after_commit callback."
    )

    register(
      id: "external-service-in-transaction",
      category: :transaction,
      severity: :high,
      message: "External service call `%{snippet}` runs inside %{scope}",
      remedy: "Third party clients hold the connection and the row locks for their full round trip. Call them after commit."
    )

    register(
      id: "mail-in-transaction",
      category: :transaction,
      severity: :high,
      message: "Synchronous mail delivery `%{snippet}` runs inside %{scope}",
      remedy: "Use deliver_later from an after_commit callback so SMTP latency stays out of the transaction."
    )

    register(
      id: "shell-in-transaction",
      category: :transaction,
      severity: :high,
      message: "Subprocess `%{snippet}` runs inside %{scope}",
      remedy: "Shelling out blocks the connection for an unbounded time. Run it after the transaction commits."
    )

    register(
      id: "sleep-in-transaction",
      category: :transaction,
      severity: :high,
      message: "`%{snippet}` deliberately blocks inside %{scope}",
      remedy: "Sleeping while holding row locks stalls every writer behind you. Sleep outside the transaction."
    )

    register(
      id: "job-enqueue-in-transaction",
      category: :transaction,
      severity: :medium,
      message: "Background job `%{snippet}` is enqueued inside %{scope}",
      remedy: "The worker can pick the job up before the transaction commits and read stale or missing rows. Enqueue from after_commit."
    )

    register(
      id: "upload-in-transaction",
      category: :transaction,
      severity: :medium,
      message: "Attachment operation `%{snippet}` runs inside %{scope}",
      remedy: "Active Storage uploads to object storage over the network. Attach after commit or upload before opening the transaction."
    )

    register(
      id: "iteration-in-transaction",
      category: :transaction,
      severity: :medium,
      message: "Loop `%{snippet}` performs database work per iteration inside %{scope}",
      remedy: "Transaction duration grows with collection size. Batch the writes or move the loop outside the transaction."
    )

    register(
      id: "broadcast-in-transaction",
      category: :transaction,
      severity: :medium,
      message: "Broadcast `%{snippet}` is pushed inside %{scope}",
      remedy: "Rendering and pushing before the commit lets subscribers see rows that are not committed yet, " \
              "or that roll back. Broadcast from after_commit."
    )

    register(
      id: "dynamic-dispatch-in-transaction",
      category: :transaction,
      severity: :low,
      message: "`%{snippet}` dispatches to a name txray cannot resolve inside %{scope}",
      remedy: "Static analysis stops here. Check by hand that the target does no network or filesystem work, or enable the runtime guard."
    )

    register(
      id: "blocking-io-in-transaction",
      category: :transaction,
      severity: :medium,
      message: "File or media work `%{snippet}` runs inside %{scope}",
      remedy: "Parsing, rendering and image processing scale with input size. Do the work before opening the transaction."
    )

    register(
      id: "cache-in-transaction",
      category: :transaction,
      severity: :low,
      message: "Cache or key value call `%{snippet}` runs inside %{scope}",
      remedy: "A cache round trip is still network latency held against an open transaction. Read it before the transaction."
    )
  end
end
