require 'sidekiq'

module Paperclip
  module Storage
    # Sidekiq worker to perform delayed uploads in storage-agnostic way.
    class DelayedUpload
      include ::Sidekiq::Worker
      sidekiq_options queue: :paperclip

      class << self
        def upload_later(attachment, store_id)
          instance = attachment.instance
          perform_async(
            instance.class.name,
            instance.id,
            attachment.class.attachment_name,
            store_id
          )
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
        Rollbar.warn(e, file_name: e.message.split(' - ')[-1])
      end
    end
  end
end
