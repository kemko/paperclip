# frozen_string_literal: true

require 'fastimage'

require 'paperclip/styles_parser'
require 'active_support/core_ext/module/delegation'
require 'active_support/core_ext/string/inflections'

module Paperclip
  # The Attachment class manages the files for a given attachment. It saves
  # when the model saves, deletes when the model is destroyed, and processes
  # the file upon assignment.
  class Attachment
    include IOStream

    MAX_FILE_NAME_LENGTH = 100
    MAX_IMAGE_RESOLUTION = 8192

    def self.default_options
      @default_options ||= {
        url: "/system/:attachment/:id/:style/:filename",
        path: ":rails_root/public:url",
        styles: {},
        default_url: "/:attachment/:style/missing.png",
        default_style: :original,
        storage: :filesystem,
        whiny: true,

        # upstream paperclip has /[&$+,\/:;=?@<>\[\]\{\}\|\\\^~%# ]/
        # \p{Word} == [[:word:]] == [Letter, Mark, Number, Connector_Punctuation]
        restricted_characters: /[^[[:word:]]\.\-]|(^\.{0,2}$)+/,
        filename_sanitizer: nil
      }
    end

    class << self
      # Every attachment definition creates separate class which stores configuration.
      # This class is instantiated later with model instance.
      def build_class(name, options = {})
        options = default_options.merge(options)
        storage_name = options.fetch(:storage).to_s.downcase.camelize
        storage_module = Storage.const_get(storage_name, false)
        Class.new(self) do
          include storage_module
          setup(name, options)
        end
      end

      # Basic attrs
      attr_reader :attachment_name, :options, :validations

      # Extracted from options
      attr_reader :url_template, :path_template, :default_url, :processing_url,
        :styles, :all_styles, :default_style, :whiny

      def setup(name, options)
        @attachment_name  = name
        @options          = options
        @validations      = []
        @url_template     = options[:url]
        @path_template    = options[:path]
        @default_url      = options[:default_url]
        @processing_url   = options[:processing_url] || default_url
        @styles           = StylesParser.new(options).styles
        @all_styles       = [:original, *styles.keys].uniq
        @default_style    = options[:default_style]
        @whiny            = options[:whiny_thumbnails] || options[:whiny]
      end

      # For delayed_paperclip
      delegate :[], :[]=, to: :options
    end

    delegate :options, :styles, :default_style, to: :class

    attr_reader :instance

    attr_accessor :post_processing

    # Creates an Attachment object. +name+ is the name of the attachment,
    # +instance+ is the ActiveRecord object instance it's attached to.
    def initialize(instance)
      @instance = instance
      @post_processing = true
    end

    def name
      self.class.attachment_name
    end

    def queued_for_delete
      @queued_for_delete ||= []
    end

    def queued_for_write
      @queued_for_write ||= {}
    end

    # What gets called when you call instance.attachment = File. It clears
    # errors, assigns attributes, processes the file, and runs validations. It
    # also queues up the previous file for deletion, to be flushed away on
    # #save of its host.  In addition to form uploads, you can also assign
    # another Paperclip attachment:
    #   new_user.avatar = old_user.avatar
    # If the file that is assigned is not valid, the processing (i.e.
    # thumbnailing, etc) will NOT be run.
    def assign uploaded_file
      ensure_required_accessors!

      # загрузка через nginx
      if uploaded_file.is_a?(Hash) && uploaded_file.has_key?('original_name')
        u = uploaded_file
        uploaded_file = FastUploadFile.new(uploaded_file)
        log "fast upload: #{u.inspect}"
      end

      if uploaded_file.is_a?(Paperclip::Attachment)
        uploaded_file = uploaded_file.to_file(:original)
        close_uploaded_file = uploaded_file.respond_to?(:close)
      end

      if image_content_type?(uploaded_file)
        # FastImage don`t rewind file if it was read before.
        uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
        sizes = FastImage.size(uploaded_file)

        unless valid_image_resolution?(sizes)
          errors[:base] = :too_large_resolution
          @validated = true # Skip other validations to prevent unnecessary messages
          return
        end
      end

      return unless valid_assignment?(uploaded_file)

      uploaded_file.binmode if uploaded_file.respond_to? :binmode
      self.clear

      return if uploaded_file.nil?

      queued_for_write[:original] = to_tempfile(uploaded_file)

      file_name = uploaded_file.original_filename
      sanitizer = self.class.options[:filename_sanitizer]
      file_name = sanitizer ? sanitizer.call(file_name, self) : sanitize_filename(file_name)

      instance_write(:file_name,       file_name)
      instance_write(:content_type,    uploaded_file.content_type.to_s.strip)
      instance_write(:file_size,       uploaded_file.size.to_i)
      instance_write(:updated_at,      Time.now)
      if sizes && sizes[0] && sizes[1]
        instance_write(:width, sizes[0])
        instance_write(:height, sizes[1])
      end

      @dirty = true

      post_process if post_processing && valid?

      updater = :"#{name}_file_name_will_change!"
      instance.send updater if instance.respond_to? updater
      # Reset the file size if the original file was reprocessed.
      instance_write(:file_size, queued_for_write[:original].size.to_i)
    ensure
      uploaded_file.close if close_uploaded_file
      validate
    end

    def image_content_type?(file)
      file.respond_to?(:content_type) && file.content_type.try(:include?, 'image')
    end

    def valid_image_resolution?(sizes)
      return true unless sizes && sizes[0] && sizes[1]

      sizes[0] <= MAX_IMAGE_RESOLUTION && sizes[1] <= MAX_IMAGE_RESOLUTION
    end

    # Returns the public URL of the attachment, with a given style. Note that
    # this does not necessarily need to point to a file that your web server
    # can access and can point to an action in your app, if you need fine
    # grained security.  This is not recommended if you don't need the
    # security, however, for performance reasons.  set
    # include_updated_timestamp to false if you want to stop the attachment
    # update time appended to the url
    def url style = default_style, include_updated_timestamp = true
      # for delayed_paperclip
      return interpolate(self.class.processing_url, style) if instance.try("#{name}_processing?")
      url = original_filename.nil? ? interpolate(self.class.default_url, style) : storage_url(style)
      return url unless include_updated_timestamp && (time_param = updated_at)
      "#{url}#{url.include?("?") ? "&" : "?"}#{time_param}"
    end

    def storage_url(style = default_style)
      interpolate(self.class.url_template, style)
    end

    # Returns the path of the attachment as defined by the :path option. If the
    # file is stored in the filesystem the path refers to the path of the file
    # on disk. If the file is stored in S3, the path is the "key" part of the
    # URL, and the :bucket option refers to the S3 bucket.
    def path style = default_style
      return if original_filename.nil?
      interpolate(self.class.path_template, style)
    end

    # Alias to +url+
    def to_s style = nil
      url(style)
    end

    # Returns true if there are no errors on this attachment.
    def valid?
      validate
      errors.empty?
    end

    # Returns an array containing the errors on this attachment.
    def errors
      @errors ||= {}
    end

    # Returns true if there are changes that need to be saved.
    def dirty?
      return false unless defined?(@dirty)
      @dirty || false
    end

    # Saves the file, if there are no errors. If there are, it flushes them to
    # the instance's errors and returns false, cancelling the save.
    def save
      if valid?
        flush_deletes
        flush_writes
        @dirty = false
        true
      else
        flush_errors
        false
      end
    end

    # Clears out the attachment. Has the same effect as previously assigning
    # nil to the attachment. Does NOT save. If you wish to clear AND save,
    # use #destroy.
    def clear
      queue_existing_for_delete
      errors.clear
      @validated = false
    end

    # Destroys the attachment. Has the same effect as previously assigning
    # nil to the attachment *and saving*. This is permanent. If you wish to
    # wipe out the existing attachment but not save, use #clear.
    def destroy
      clear
      save
    end

    # Returns the name of the file as originally assigned, and lives in the
    # <attachment>_file_name attribute of the model.
    def original_filename
      instance_read(:file_name)
    end

    # Returns the size of the file as originally assigned, and lives in the
    # <attachment>_file_size attribute of the model.
    def size
      instance_read(:file_size) || (queued_for_write[:original] && queued_for_write[:original].size)
    end

    # Returns the content_type of the file as originally assigned, and lives
    # in the <attachment>_content_type attribute of the model.
    def content_type
      instance_read(:content_type)
    end

    def to_file(style = default_style)
      file = queued_for_write[style]
      file&.rewind
      file
    end

    def to_io(*args)
      to_file(*args)
    end

    # Returns the last modified time of the file as originally assigned, and
    # lives in the <attachment>_updated_at attribute of the model.
    def updated_at
      time = instance_read(:updated_at)
      time && time.to_i
    end

    def sanitize_filename(file_name)
      file_name = file_name.strip

      restricted_characters = self.class.options[:restricted_characters]
      file_name.gsub!(restricted_characters, '_') if restricted_characters

      # Укорачиваем слишком длинные имена файлов.
      if file_name.length > MAX_FILE_NAME_LENGTH
        # 1 символ имени и точка и того - 2
        ext = file_name.match(/\.(\w{0,#{MAX_FILE_NAME_LENGTH - 2}})$/) ? $1 : ""
        # 1 - из-за того что отсчет идет от 0, и еще 1 из-за точки, и того 2
        file_name = file_name[0..(MAX_FILE_NAME_LENGTH - 2 - ext.length)]
        file_name << ".#{ext}" if !ext.blank?
      end
      file_name
    end

    # This method really shouldn't be called that often. It's expected use is
    # in the paperclip:refresh rake task and that's it. It will regenerate all
    # thumbnails forcefully, by reobtaining the original file and going through
    # the post-process again.
    def reprocess!
      new_original = Tempfile.new("paperclip-reprocess-#{instance.id}-")
      new_original.binmode
      old_original = to_file(:original)
      new_original.write( old_original.read )
      new_original.rewind
      @queued_for_write = { :original => new_original }
      post_process
      old_original.close if old_original.respond_to?(:close)
      save
    end

    # Returns true if a file has been assigned.
    def file?
      !original_filename.blank?
    end

    # Writes the attachment-specific attribute on the instance. For example,
    # instance_write(:file_name, "me.jpg") will write "me.jpg" to the instance's
    # "avatar_file_name" field (assuming the attachment is called avatar).
    def instance_write(attr, value)
      setter = :"#{name}_#{attr}="
      responds = instance.respond_to?(setter)
      self.instance_variable_set("@_#{setter.to_s.chop}", value)
      instance.send(setter, value) if responds || attr.to_s == "file_name"
    end

    # Reads the attachment-specific attribute on the instance. See instance_write
    # for more details.
    def instance_read(attr)
      getter = :"#{name}_#{attr}"
      if instance_variable_defined?("@_#{getter}")
        cached = instance_variable_get("@_#{getter}")
        return cached if cached
      end
      responds = instance.respond_to?(getter)
      instance.send(getter) if responds || attr.to_s == "file_name"
    end

    private

    def ensure_required_accessors! #:nodoc:
      %w(file_name).each do |field|
        unless instance.respond_to?("#{name}_#{field}") && instance.respond_to?("#{name}_#{field}=")
          raise PaperclipError.new("#{instance.class} model missing required attr_accessor for '#{name}_#{field}'")
        end
      end
    end

    def log message #:nodoc:
      Paperclip.log(message)
    end

    def valid_assignment? file #:nodoc:
      file.nil? || (file.respond_to?(:original_filename) && file.respond_to?(:content_type))
    end

    def validate #:nodoc:
      @validated ||= begin # rubocop:disable Naming/MemoizedInstanceVariableName
        self.class.validations.each do |validation|
          name, options = validation
          error = send(:"validate_#{name}", options) if allow_validation?(options)
          errors[name] = error if error
        end
        true
      end
    end

    def allow_validation? options #:nodoc:
      (options[:if].nil? || check_guard(options[:if])) && (options[:unless].nil? || !check_guard(options[:unless]))
    end

    def check_guard guard #:nodoc:
      if guard.respond_to? :call
        guard.call(instance)
      elsif ! guard.blank?
        instance.send(guard.to_s)
      end
    end

    def validate_size options #:nodoc:
      if file? && !options[:range].include?(size.to_i)
        options[:message]#.gsub(/:min/, options[:min].to_s).gsub(/:max/, options[:max].to_s)
      end
    end

    def validate_presence options #:nodoc:
      options[:message] unless file?
    end

    def validate_content_type options #:nodoc:
      valid_types = [options[:content_type]].flatten
      unless original_filename.blank?
        unless valid_types.blank?
          content_type = instance_read(:content_type)
          unless valid_types.any?{|t| content_type.nil? || t === content_type }
            options[:message] || "is not one of the allowed file types."
          end
        end
      end
    end

    def post_process #:nodoc:
      return unless subject_to_post_process?
      return if queued_for_write[:original].nil?

      instance.run_paperclip_callbacks(:post_process) do
        instance.run_paperclip_callbacks(:"#{name}_post_process") do
          post_process_styles
        end
      end
    end

    def post_process_styles #:nodoc:
      styles.each do |name, args|
        begin
          raise RuntimeError.new("Style #{name} has no processors defined.") if args[:processors].blank?
          queued_for_write[name] = args[:processors].inject(queued_for_write[:original]) do |file, processor|
            Paperclip.processor(processor).make(file, args, self)
          end
        rescue PaperclipError => e
          log("An error was received while processing: #{e.inspect}")
          (errors[:processing] ||= []) << e.message if self.class.whiny
        end
      end
    end

    def interpolate pattern, style = default_style #:nodoc:
      Paperclip::Interpolations.interpolate(pattern, self, style)
    end

    def queue_existing_for_delete #:nodoc:
      return unless file?
      action = delete_styles_later(self.class.all_styles)
      queued_for_delete << action if action
    end

    def flush_deletes
      queued_for_delete.each(&:call)
      queued_for_delete.clear
    end

    def flush_errors #:nodoc:
      errors.each do |_error, message|
        [message].flatten.each {|m| instance.errors.add(name, m) }
      end
    end

    # Create tempfile with given content.
    # Keeps original extension, and prefix from original basename.
    def create_tempfile(body)
      filename = instance_read(:file_name)
      extname = File.extname(original_filename)
      basename = File.basename(filename, extname)
      file = Tempfile.new([basename, extname]).tap do |tfile|
        tfile.binmode
        tfile.original_filename = "#{basename}.#{extname}"
      end
      file.original_filename = filename
      file.write(body)
      file.tap(&:flush).tap(&:rewind)
    end

    def subject_to_post_process?
      content_type.include?('image') && !content_type.include?('svg')
    end
  end
end
