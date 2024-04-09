require 'open3'

module Paperclip
  class Optimizer < Processor
    def make
      optimized_file = optimize(@file)
      return @file unless optimized_file && optimized_file.size > 0 # rubocop:disable Style/ZeroLengthPredicate

      optimized_file
    end

    def real_content_type
      Paperclip::Upfile.content_type_from_file(@file.path)
    end

    def optimize(_file)
      # TODO: use the arg?
      src = @file.path
      dst_file = Tempfile.new(["#{File.basename(src)}-optim", File.extname(src)])
      dst_file.binmode
      src_shell = src.shellescape
      dst_shell = dst_file.path.shellescape
      cmd = case real_content_type
            when 'image/jpeg', 'image/jpg', 'image/pjpeg'
              # TODO: --stdout > #{dst_shell}
              "cp #{src_shell} #{dst_shell} && jpegoptim --all-progressive -q --strip-com --strip-exif --strip-iptc -- #{dst_shell}"
            when 'image/png', 'image/x-png'
              "pngcrush -rem alla -q #{src_shell} #{dst_shell}"
            when 'image/gif'
              "gifsicle -o #{dst_shell} -O3 --no-comments --no-names --same-delay --same-loopcount --no-warnings -- #{src_shell}"
            else
              return
            end
      run_and_verify!(cmd)
      dst_file
    rescue StandardError => e
      dst_file.close!
      Paperclip.log("Error: cannot optimize: #{e}")
      nil
    end

    private
    def run_and_verify!(cmd)
      # Checking stdout and stderr because pngcrush always has exit code of zero
      Open3.capture3(cmd)
    end
  end
end
