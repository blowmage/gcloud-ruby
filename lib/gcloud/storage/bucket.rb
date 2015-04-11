#--
# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "gcloud/storage/bucket/acl"
require "gcloud/storage/bucket/list"
require "gcloud/storage/file"

module Gcloud
  module Storage
    ##
    # Represents a Bucket. Belongs to a Project and has many Files.
    class Bucket
      ##
      # The Connection object.
      attr_accessor :connection #:nodoc:

      ##
      # The Google API Client object.
      attr_accessor :gapi #:nodoc:

      ##
      # Create an empty Bucket object.
      def initialize
        @connection = nil
        @gapi = {}
      end

      ##
      # The kind of item this is.
      # For buckets, this is always storage#bucket.
      def kind
        @gapi["kind"]
      end

      ##
      # The ID of the bucket.
      def id
        @gapi["id"]
      end

      ##
      # The name of the bucket.
      def name
        @gapi["name"]
      end

      ##
      # The URI of this bucket.
      def url
        @gapi["selfLink"]
      end

      ##
      # The location of the bucket.
      # Object data for objects in the bucket resides in physical
      # storage within this region. Defaults to US.
      # See the developer's guide for the authoritative list.
      #
      # https://cloud.google.com/storage/docs/concepts-techniques
      def location
        @gapi["location"]
      end

      ##
      # Creation time of the bucket.
      def created_at
        @gapi["timeCreated"]
      end

      ##
      # Permenently deletes the bucket.
      # The bucket must be empty.
      #
      #   bucket.delete
      #
      # The API call to delete the bucket may be retried under certain
      # conditions. See Gcloud::Backoff to control this behavior, or
      # specify the wanted behavior in the call:
      #
      #   bucket.delete retries: 5
      def delete options = {}
        ensure_connection!
        resp = connection.delete_bucket name, options
        if resp.success?
          true
        else
          ApiError.from_response(resp)
        end
      end

      ##
      # Retrieves a list of files matching the criteria.
      #
      #   storage = Gcloud.storage
      #   bucket = storage.find_bucket "my-bucket"
      #   files = bucket.files
      #   files.each do |file|
      #     puts file.name
      #   end
      #
      # See Gcloud::Storage::File
      def files options = {}
        ensure_connection!
        resp = connection.list_files name, options
        if resp.success?
          File::List.from_resp resp, connection
        else
          fail ApiError.from_response(resp)
        end
      end

      ##
      # Retrieves a file matching the path.
      #
      #   storage = Gcloud.storage
      #   bucket = storage.find_bucket "my-bucket"
      #   file = bucket.find_file "path/to/my-file.ext"
      #   puts file.name
      #
      # See Gcloud::Storage::File
      def find_file path, options = {}
        ensure_connection!
        resp = connection.get_file name, path, options
        if resp.success?
          File.from_gapi resp.data, connection
        else
          fail ApiError.from_response(resp)
        end
      end

      ##
      # Create a new Gcloud::Storeage::File object by providing a
      # File object to upload and the path to store it with.
      #
      #   storage = Gcloud.storage
      #   bucket = storage.find_bucket "my-bucket"
      #   bucket.create_file "path/to/local.file.ext"
      #
      # Additionally, a destination path can be specified.
      #
      #   storage = Gcloud.storage
      #   bucket = storage.find_bucket "my-bucket"
      #   bucket.create_file "path/to/local.file.ext",
      #                      "destination/path/file.ext"
      #
      # A chunk_size value can be provided in the options to be used
      # in resumable uploads. This value is the number of bytes per
      # chunk and must be divisible by 256KB. If it is not divisible
      # by 265KB then it will be lowered to the nearest acceptible
      # value.
      #
      #   bucket.create_file "path/to/local.file.ext",
      #                      "destination/path/file.ext",
      #                      chunk_size: 1024*1024 # 1 MB chunk
      #
      # See Gcloud::Storage::File
      def create_file file, path = nil, options = {}
        ensure_connection!
        # TODO: Raise if file doesn't exist
        # ensure_file_exists!
        fail unless ::File.file? file

        options[:acl] = File::Acl.predefined_rule_for options[:acl]

        if resumable_upload? file
          upload_resumable file, path, options[:chunk_size], options
        else
          upload_multipart file, path, options
        end
      end

      ##
      # Access Control List
      def acl
        @acl ||= Bucket::Acl.new self
      end

      ##
      # Default Access Control List
      def default_acl
        @default_acl ||= Bucket::DefaultAcl.new self
      end

      ##
      # New Bucket from a Google API Client object.
      def self.from_gapi gapi, conn #:nodoc:
        new.tap do |f|
          f.gapi = gapi
          f.connection = conn
        end
      end

      protected

      ##
      # Raise an error unless an active connection is available.
      def ensure_connection!
        fail "Must have active connection" unless connection
      end

      ##
      # Determines if a resumable upload should be used.
      def resumable_upload? file #:nodoc:
        ::File.size?(file).to_i > Storage.resumable_threshold
      end

      def upload_multipart file, path, options = {}
        resp = @connection.insert_file_multipart name, file, path, options

        if resp.success?
          File.from_gapi resp.data, connection
        else
          fail ApiError.from_response(resp)
        end
      end

      def upload_resumable file, path, chunk_size, options = {}
        chunk_size = verify_chunk_size! chunk_size

        resp = @connection.insert_file_resumable name, file,
                                                 path, chunk_size, options

        if resp.success?
          File.from_gapi resp.data, connection
        else
          fail ApiError.from_response(resp)
        end
      end

      ##
      # Determines if a chunk_size is valid.
      def verify_chunk_size! chunk_size
        chunk_size = chunk_size.to_i
        chunk_mod = 256 * 1024 # 256KB
        if (chunk_size.to_i % chunk_mod) != 0
          chunk_size = (chunk_size / chunk_mod) * chunk_mod
        end
        return if chunk_size.zero?
        chunk_size
      end
    end
  end
end
