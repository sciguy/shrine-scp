require "shrine"

require "fileutils"
require "tempfile"

class Shrine
  module Storage
    class Scp
      attr_reader :directory, :ssh_host, :host, :prefix, :options, :permissions

      def initialize(directory:, ssh_host: nil, host: nil, prefix: nil, options: %w[-q], permissions: 0600)
        # Initializes a storage for uploading via scp.
        #
        # :directory
        # :  the path where files will be transferred to
        #
        # :ssh_host
        # :  optional user@hostname for remote scp transfers over ssh
        #
        # :host
        # :  URLs will by default be relative if `:prefix` is set, and you
        #    can use this option to set a CDN host (e.g. `//abc123.cloudfront.net`).
        #
        # :prefix
        # :  The directory relative to `directory` to which files will be stored,
        #    and it is included in the URL.
        #
        # :options
        # :  Additional arguments specific to scp
        #    https://linux.die.net/man/1/scp
        #
        # :permissions
        # :  bit pattern for permissions to set on uploaded files
        #
        @directory   = directory.chomp(File::SEPARATOR)
        @ssh_host    = ssh_host
        @host        = host.chomp(File::SEPARATOR) if host
        @prefix      = prefix.chomp(File::SEPARATOR) if prefix
        @options     = options
        @permissions = permissions
      end

      def upload(io, id, **)
        file = write_io(io, id)
        scp_up(id, file.path)
        file
      end

      def download(id)
        file = scp_down(id)
        file
      end

      def open(id, **options)
        file = scp_down(id)
        raise Shrine::FileNotFound unless file
        file.tap(&:open)
      end

      def exists?(id)
        file_path = File.join(directory, id)
        bash "ls -la #{file_path}"
      end

      def url(id, **_options)
        File.join([host, prefix, id].compact)
      end

      def delete(id)
        file_path = path(id)
        bash "rm -rf #{file_path}"
      end

      def clear!
        file_path = path("*")
        bash "rm -rf #{file_path}"
      end

      private

        def ssh?
          ssh_host
        end

        def bash(sh)
          command = "bash -c '#{sh}' > /dev/null 2>&1; echo $?"
          command = "ssh #{ssh_host} \"#{command}\"" if ssh_host
          `#{command}`.chomp == "0"
        end

        def scp_up(id, tmp_path)
          FileUtils.chmod(permissions, tmp_path)
          destination = path(id)
          bash "mkdir -p #{File.dirname(destination)}"
          destination = "#{ssh_host}:#{destination}" if ssh_host
          scp_transfer(source: tmp_path, destination: destination)
        end

        def scp_down(id)
          source = path(id)
          source = "#{ssh_host}:#{source}" if ssh_host
          tmp = tempfile!(id)

          tmp if scp_transfer(source: source, destination: tmp.path)
        end

        def scp_transfer(source:, destination:)
          command = [scp_bin, scp_options, source, destination].join(" ")
          system command
        end

        def scp_bin
          scp_bin = `which scp`.chomp
          raise "scp could not be found." if scp_bin.empty?
          scp_bin
        end

        def scp_options
          options.join(" ")
        end

        def path(id)
          File.join([directory, prefix, id].compact)
        end

        def tempfile!(id)
          Tempfile.new(["shrine-scp-", File.extname(id)], binmode: true)
        end

        def write_io(io, id)
          tmp = tempfile!(id)
          IO.copy_stream(io, tmp)
          tmp.tap(&:open)
          tmp
        end
    end
  end
end
