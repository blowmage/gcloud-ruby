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
require "gcloud/upload"

module Gcloud
  module Storage
    ##
    # = Bucket
    #
    # Represents a Storage bucket. Belongs to a Project and has many Files.
    #
    #   require "gcloud"
    #
    #   gcloud = Gcloud.new
    #   storage = gcloud.storage
    #
    #   bucket = storage.bucket "my-bucket"
    #   file = bucket.file "path/to/my-file.ext"
    #
    class Bucket
      ##
      # The Connection object.
      attr_accessor :connection #:nodoc:

      ##
      # The Google API Client object.
      attr_accessor :gapi #:nodoc:

      ##
      # Create an empty Bucket object.
      def initialize #:nodoc:
        @connection = nil
        @gapi = {}
      end

      ##
      # The kind of item this is.
      # For buckets, this is always +storage#bucket+.
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
      def cors
        g = @gapi
        g = g.to_hash if g.respond_to? :to_hash
        c = g["cors"] ||= [] # consider freezing the array so no updates?
        # return c unless block_given?
        # cors = Cors.new c
        # yield cors
        # self.cors = cors.cors if cors.changed?
      end

      def cors= new_cors
        patch_gapi! cors: new_cors
      end

      ##
      # Permenently deletes the bucket.
      # The bucket must be empty before it can be deleted.
      #
      # === Parameters
      #
      # +options+::
      #   An optional Hash for controlling additional behavior. (+Hash+)
      # <code>options[:retries]</code>::
      #   The number of times the API call should be retried.
      #   Default is Gcloud::Backoff.retries. (+Integer+)
      #
      # === Returns
      #
      # +true+ if the bucket was deleted.
      #
      # === Examples
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #   bucket.delete
      #
      # The API call to delete the bucket may be retried under certain
      # conditions. See Gcloud::Backoff to control this behavior, or
      # specify the wanted behavior in the call:
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #   bucket.delete retries: 5
      #
      def delete options = {}
        ensure_connection!
        resp = connection.delete_bucket name, options
        if resp.success?
          true
        else
          fail ApiError.from_response(resp)
        end
      end

      ##
      # Retrieves a list of files matching the criteria.
      #
      # === Parameters
      #
      # +options+::
      #   An optional Hash for controlling additional behavior. (+Hash+)
      # <code>options[:prefix]</code>::
      #   Filter results to files whose names begin with this prefix.
      #   (+String+)
      # <code>options[:token]</code>::
      #   A previously-returned page token representing part of the larger set
      #   of results to view. (+String+)
      # <code>options[:max]</code>::
      #   Maximum number of items plus prefixes to return. As duplicate prefixes
      #   are omitted, fewer total results may be returned than requested.
      #   The default value of this parameter is 1,000 items. (+Integer+)
      # <code>options[:versions]</code>::
      #   If +true+, lists all versions of an object as distinct results.
      #   The default is +false+. For more information, see
      #   {Object Versioning
      #   }[https://cloud.google.com/storage/docs/object-versioning].
      #   (+Boolean+)
      # <code>options[:max]</code>::
      #   Maximum number of buckets to return. (+Integer+)
      #
      # === Returns
      #
      # Array of Gcloud::Storage::File (Gcloud::Storage::File::List)
      #
      # === Examples
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #   files = bucket.files
      #   files.each do |file|
      #     puts file.name
      #   end
      #
      # If you have a significant number of files, you may need to paginate
      # through them: (See File::List#token)
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #
      #   all_files = []
      #   tmp_files = bucket.files
      #   while tmp_files.any? do
      #     tmp_files.each do |file|
      #       all_files << file
      #     end
      #     # break loop if no more buckets available
      #     break if tmp_files.token.nil?
      #     # get the next group of files
      #     tmp_files = bucket.files token: tmp_files.token
      #   end
      #
      def files options = {}
        ensure_connection!
        resp = connection.list_files name, options
        if resp.success?
          File::List.from_response resp, connection
        else
          fail ApiError.from_response(resp)
        end
      end
      alias_method :find_files, :files

      ##
      # Retrieves a file matching the path.
      #
      # === Parameters
      #
      # +path+::
      #   Name (path) of the file. (+String+)
      #
      # === Returns
      #
      # Gcloud::Storage::File or nil if file does not exist
      #
      # === Example
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #
      #   file = bucket.file "path/to/my-file.ext"
      #   puts file.name
      #
      def file path, options = {}
        ensure_connection!
        resp = connection.get_file name, path, options
        if resp.success?
          File.from_gapi resp.data, connection
        else
          fail ApiError.from_response(resp)
        end
      end
      alias_method :find_file, :file

      ##
      # Create a new File object by providing a path to a local file to upload
      # and the path to store it with in the bucket.
      #
      # === Parameters
      #
      # +file+::
      #   Path of the file on the filesystem to upload. (+String+)
      # +path+::
      #   Path to store the file in Google Cloud Storage. (+String+)
      # +options+::
      #   An optional Hash for controlling additional behavior. (+Hash+)
      # <code>options[:acl]</code>::
      #   A predefined set of access controls to apply to this file.
      #   (+String+)
      #
      #   Acceptable values are:
      #   * +auth+, +auth_read+, +authenticated+, +authenticated_read+,
      #     +authenticatedRead+ - File owner gets OWNER access, and
      #     allAuthenticatedUsers get READER access.
      #   * +owner_full+, +bucketOwnerFullControl+ - File owner gets OWNER
      #     access, and project team owners get OWNER access.
      #   * +owner_read+, +bucketOwnerRead+ - File owner gets OWNER access, and
      #     project team owners get READER access.
      #   * +private+ - File owner gets OWNER access.
      #   * +project_private+, +projectPrivate+ - File owner gets OWNER access,
      #     and project team members get access according to their roles.
      #   * +public+, +public_read+, +publicRead+ - File owner gets OWNER
      #     access, and allUsers get READER access.
      #
      # === Returns
      #
      # Gcloud::Storage::File
      #
      # === Examples
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #
      #   bucket.create_file "path/to/local.file.ext"
      #
      # Additionally, a destination path can be specified.
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #
      #   bucket.create_file "path/to/local.file.ext",
      #                      "destination/path/file.ext"
      #
      # A chunk_size value can be provided in the options to be used
      # in resumable uploads. This value is the number of bytes per
      # chunk and must be divisible by 256KB. If it is not divisible
      # by 265KB then it will be lowered to the nearest acceptible
      # value.
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-bucket"
      #
      #   bucket.create_file "path/to/local.file.ext",
      #                      "destination/path/file.ext",
      #                      chunk_size: 1024*1024 # 1 MB chunk
      #
      # ==== A note about large uploads
      #
      # You may encounter a broken pipe error while attempting to upload large
      # files. To avoid this problem, add
      # {httpclient}[https://rubygems.org/gems/httpclient] as a dependency to
      # your project, and configure {Faraday}[https://rubygems.org/gems/faraday]
      # to use it, after requiring Gcloud, but before initiating your Gcloud
      # connection.
      #
      #   require "gcloud"
      #
      #   Faraday.default_adapter = :httpclient
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #   bucket = storage.bucket "my-todo-app"
      #
      def create_file file, path = nil, options = {}
        ensure_connection!
        ensure_file_exists! file

        options[:acl] = File::Acl.predefined_rule_for options[:acl]

        if resumable_upload? file
          upload_resumable file, path, options[:chunk_size], options
        else
          upload_multipart file, path, options
        end
      end
      alias_method :upload_file, :create_file
      alias_method :new_file, :create_file

      ##
      # The Bucket::Acl instance used to control access to the bucket.
      #
      # A bucket has owners, writers, and readers. Permissions can be granted to
      # an individual user's email address, a group's email address, as well as
      # many predefined lists. See the
      # {Access Control guide
      # }[https://cloud.google.com/storage/docs/access-control]
      # for more.
      #
      # === Examples
      #
      # Access to a bucket can be granted to a user by appending +"user-"+ to
      # the email address:
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-todo-app"
      #
      #   email = "heidi@example.net"
      #   bucket.acl.add_reader "user-#{email}"
      #
      # Access to a bucket can be granted to a group by appending +"group-"+ to
      # the email address:
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-todo-app"
      #
      #   email = "authors@example.net"
      #   bucket.acl.add_reader "group-#{email}"
      #
      # Access to a bucket can also be granted to a predefined list of
      # permissions:
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-todo-app"
      #
      #   bucket.acl.public!
      #
      def acl
        @acl ||= Bucket::Acl.new self
      end

      ##
      # The Bucket::DefaultAcl instance used to control access to the bucket's
      # files.
      #
      # A bucket's files have owners, writers, and readers. Permissions can be
      # granted to an individual user's email address, a group's email address,
      # as well as many predefined lists. See the
      # {Access Control guide
      # }[https://cloud.google.com/storage/docs/access-control]
      # for more.
      #
      # === Examples
      #
      # Access to a bucket's files can be granted to a user by appending
      # +"user-"+ to the email address:
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-todo-app"
      #
      #   email = "heidi@example.net"
      #   bucket.default_acl.add_reader "user-#{email}"
      #
      # Access to a bucket's files can be granted to a group by appending
      # +"group-"+ to the email address:
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-todo-app"
      #
      #   email = "authors@example.net"
      #   bucket.default_acl.add_reader "group-#{email}"
      #
      # Access to a bucket's files can also be granted to a predefined list of
      # permissions:
      #
      #   require "gcloud"
      #
      #   gcloud = Gcloud.new
      #   storage = gcloud.storage
      #
      #   bucket = storage.bucket "my-todo-app"
      #
      #   bucket.default_acl.public!
      def default_acl
        @default_acl ||= Bucket::DefaultAcl.new self
      end

      ##
      # Reloads the bucket with current data from the Storage service.
      def reload!
        ensure_connection!
        resp = connection.get_bucket name
        if resp.success?
          @gapi = resp.data
        else
          fail ApiError.from_response(resp)
        end
      end
      alias_method :refresh!, :reload!

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
      # Raise an error if the file is not found.
      def ensure_file_exists! file
        return if ::File.file? file
        fail ArgumentError, "cannot find file #{file}"
      end

      ##
      # Determines if a resumable upload should be used.
      def resumable_upload? file #:nodoc:
        ::File.size?(file).to_i > Upload.resumable_threshold
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
