# frozen_string_literal: true

module Txray
  module Catalog
    HTTP_NAMESPACES = %w[
      Net::HTTP Net::HTTPS Net::FTP Net::SSH Net::SFTP Net::Telnet
      Faraday HTTParty RestClient Excon Typhoeus HTTPX HTTPClient Curl Patron Mechanize Down
      OpenURI Socket TCPSocket
    ].freeze

    SERVICE_NAMESPACES = %w[
      Stripe Braintree PayPal Recurly Chargebee Coinbase Plaid Adyen Square
      Aws AWS Azure Google GoogleDrive Firebase Cloudinary Imgix
      Twilio SendGrid Mailgun Postmark Mailchimp Customerio Intercom Zendesk Front
      Slack Discordrb Octokit Gitlab Shopify Salesforce Hubspot Airtable Notion
      Algolia Elasticsearch OpenSearch Meilisearch Typesense
      Pusher Ably Segment Mixpanel Amplitude Posthog
      OpenAI Anthropic Gemini Replicate Pinecone
      Onfido Persona Checkr Twitter Linkedin Zoom
    ].freeze

    CACHE_NAMESPACES = %w[Redis Dalli Memcached MemCache].freeze

    SHELL_METHODS = %i[system spawn exec fork popen popen2 popen3 capture2 capture2e capture3 pipeline].freeze
    SHELL_NAMESPACES = %w[Open3 Process Kernel IO PTY].freeze

    MAIL_METHODS = %i[deliver_now deliver_now!].freeze

    ENQUEUE_METHODS = %i[
      perform_later deliver_later deliver_later! perform_async perform_in perform_at
      enqueue enqueue_at broadcast_later broadcast_later_to
    ].freeze

    ATTACHMENT_METHODS = %i[attach purge purge_later analyze processed].freeze

    ITERATOR_METHODS = %i[
      each each_with_object each_with_index each_slice each_entry map flat_map
      find_each find_in_batches in_batches collect select filter reject sum times upto downto
    ].freeze

    PERSISTENCE_METHODS = %i[
      save save! update update! update_attribute update_column update_columns
      create create! destroy destroy! delete touch increment! decrement! toggle!
      insert insert! insert_all insert_all! upsert upsert_all
      find find_by find_by! where pluck exists? reload lock! first last count
    ].freeze

    CALLBACKS = %i[
      before_validation after_validation
      before_save around_save after_save
      before_create around_create after_create
      before_update around_update after_update
      before_destroy around_destroy after_destroy
      after_touch
    ].freeze

    module_function

    def namespaced?(constant, namespaces)
      return false if constant.nil?

      namespaces.any? { |namespace| constant == namespace || constant.start_with?("#{namespace}::") }
    end
  end
end
