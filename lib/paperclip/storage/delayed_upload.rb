# frozen_string_literal: true

require 'sidekiq'

module Paperclip
  module Storage
    # Sidekiq worker to perform delayed uploads in storage-agnostic way.
    class DelayedUpload
      include ::Sidekiq::Worker
      sidekiq_options queue: :paperclip

      class << self
        def upload_later(attachment, store_id, delay = nil)
          instance = attachment.instance
          args = [
            instance.class.name,
            instance.id,
            attachment.class.attachment_name.to_s,
            store_id.to_s # args must be serializable to json without type changes thus strings only
          ]

          delay.present? ? perform_in(delay, *args) : perform_async(*args)
        end
      end

      def perform(class_name, id, attachment_name, store_id)
        model = class_name.constantize
        instance = model.find_by_id(id)
        return unless instance
        attachment = instance.public_send(attachment_name)
        attachment.upload_to(store_id)
      # Suppress errors if record was deleted.
      rescue Errno::ESTALE
        raise if model.exists?(id)
      rescue Errno::ENOENT => e
        raise if model.exists?(id)
        Rollbar.warn(e, file_name: e.message.split(' - ')[-1]) if defined?(Rollbar)
      end
    end
  end
end
