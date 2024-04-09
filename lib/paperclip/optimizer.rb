require 'open3'

module Paperclip
  class Optimizer < Processor
    def make
      optimize(@file) || @file
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
              # NB: --stdout не работает, там бывают пустые файлы если оно решило ничего не делать
              # нельзя `cp`, надо чтобы открытый файл указывал куда надо, поэтому `cat>`
              "cat #{src_shell} > #{dst_file} && jpegoptim --all-progressive -q --strip-com --strip-exif --strip-iptc -- #{dst_shell}"
            when 'image/png', 'image/x-png'
              "pngcrush -rem alla -q #{src_shell} #{dst_shell}"
            when 'image/gif'
              "gifsicle -o #{dst_shell} -O3 --no-comments --no-names --same-delay --same-loopcount --no-warnings -- #{src_shell}"
            else
              return
            end
      run_and_verify!(cmd)

      if dst_file.size == 0 # rubocop:disable Style/ZeroLengthPredicate
        dst_file.close!
        return nil
      end

      dst_file.tap(&:flush).tap(&:rewind)
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
