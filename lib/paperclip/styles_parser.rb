# frozen_string_literal: true

module Paperclip
  class StylesParser
    attr_reader :styles, :convert_options, :processors, :whiny

    def initialize(options)
      @styles = options[:styles]
      @convert_options = options[:convert_options] || {}
      @processors = options[:processors] || [:thumbnail]
      @whiny = options[:whiny_thumbnails] || options[:whiny]

      normalize_style_definition
    end

    def normalize_style_definition #:nodoc:
      styles.each do |name, args|
        styles[name] =
          if args.is_a? Hash
            {
              processors:       processors,
              whiny:            whiny,
              convert_options:  extra_options_for(name)
            }.merge(args)
          else
            dimensions, format = args
            {
              processors:       processors,
              geometry:         dimensions,
              format:           format.presence,
              whiny:            whiny,
              convert_options:  extra_options_for(name)
            }
          end
      end
    end

    def extra_options_for(style) #:nodoc:
      all_options   = convert_options[:all]
      style_options = convert_options[style]
      [style_options, all_options].compact.join(' ')
    end
  end
end
