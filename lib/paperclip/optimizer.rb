require 'open3'

module Paperclip
  class Optimizer < Processor
    def make
      optimized_file_path  = optimize(@file)
      if optimized_file_path && File.exists?(optimized_file_path)
        return File.open(optimized_file_path)
      else
        return @file
      end
    end

    def real_content_type
      out = Paperclip.run "file", "--mime-type #{@file.path.shellescape}"
      out.split(/:\s+/)[1].gsub("\n", "")
    end

    def optimize(file)
      src = @file.path
      dst = "#{src}-#{SecureRandom.hex}"
      src_shell = src.shellescape
      dst_shell = dst.shellescape
      cmd = case real_content_type
            when 'image/jpeg', 'image/jpg', 'image/pjpeg'
              "cp #{src_shell} #{dst_shell} && jpegoptim --all-progressive -q --strip-com --strip-exif --strip-iptc -- #{dst_shell}"
            when 'image/png', 'image/x-png'
              "pngcrush -rem alla -q #{src_shell} #{dst_shell}"
            when 'image/gif'
              "gifsicle -o #{dst_shell} -O3 --no-comments --no-names --same-delay --same-loopcount --no-warnings -- #{src_shell}"
            else
              return
            end
      run_and_verify!(cmd)
      dst
    end

    private
    def run_and_verify!(cmd)
      # Checking stdout and stderr because pngcrush always has exit code of zero
      Open3.capture3(cmd)
    end
  end
end
