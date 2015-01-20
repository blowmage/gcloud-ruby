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

require "pathname"
require "gcloud/version"
require "google/api_client"
require "mime/types"

module Gcloud
  module Storage
    ##
    # Represents the connection to Storage,
    # as well as expose the API calls.
    class Connection #:nodoc:
      API_VERSION = "v1"

      attr_accessor :project
      attr_accessor :credentials #:nodoc:

      ##
      # Creates a new Connection instance.
      def initialize project, credentials
        @project = project
        @credentials = credentials
        @client = Google::APIClient.new application_name:    "gcloud-ruby",
                                        application_version: Gcloud::VERSION
        @client.authorization = @credentials.client
        @storage = @client.discovered_api "storage", API_VERSION
      end

      ##
      # Retrieves a list of buckets for the given project.
      def list_buckets
        @client.execute(
          api_method: @storage.buckets.list,
          parameters: { project: @project }
        )
      end

      ##
      # Retrieves bucket by name.
      def get_bucket bucket_name
        @client.execute(
          api_method: @storage.buckets.get,
          parameters: { bucket: bucket_name }
        )
      end

      ##
      # Creates a new bucket.
      def insert_bucket bucket_name
        @client.execute(
          api_method: @storage.buckets.insert,
          parameters: { project: @project },
          body_object: { name: bucket_name }
        )
      end

      ##
      # Permenently deletes an empty bucket.
      def delete_bucket bucket_name
        @client.execute(
          api_method: @storage.buckets.delete,
          parameters: { bucket: bucket_name }
        )
      end

      ##
      # Retrieves a list of files matching the criteria.
      def list_files bucket_name
        @client.execute(
          api_method: @storage.objects.list,
          parameters: { bucket: bucket_name }
        )
      end

      # rubocop:disable Metrics/MethodLength
      # Disabled rubocop because the API we need to use
      # is verbose. No getting around it.

      ##
      # Stores a new object and metadata.
      # Uses a multipart form post.
      def insert_file_multipart bucket_name, file, path = nil
        local_path = Pathname(file).to_path
        upload_path = Pathname(path || local_path).to_path
        mime_type = mime_type_for local_path

        media = Google::APIClient::UploadIO.new local_path, mime_type

        @client.execute(
          api_method: @storage.objects.insert,
          media: media,
          parameters: {
            uploadType: "multipart",
            bucket: bucket_name,
            name: upload_path
          },
          body_object: { contentType: mime_type }
        )
      end

      ##
      # Stores a new object and metadata.
      # Uses a resumable upload.
      def insert_file_resumable bucket_name, file, path = nil, chunk_size = nil
        local_path = Pathname(file).to_path
        upload_path = Pathname(path || local_path).to_path
        # mime_type = options[:mime_type] || mime_type_for local_path
        mime_type = mime_type_for local_path

        # This comes from Faraday, which gets it from multipart-post
        # The signature is:
        # filename_or_io, content_type, filename = nil, opts = {}

        media = Google::APIClient::UploadIO.new local_path, mime_type
        media.chunk_size = chunk_size

        result = @client.execute(
          api_method: @storage.objects.insert,
          media: media,
          parameters: {
            uploadType: "resumable",
            bucket: bucket_name,
            name: upload_path
          },
          body_object: { contentType: mime_type }
        )
        upload = result.resumable_upload
        result = @client.execute upload while upload.resumable?
        result
      end

      # rubocop:enable Metrics/MethodLength

      ##
      # Retrieves an object or its metadata.
      def get_file bucket_name, file_path
        @client.execute(
          api_method: @storage.objects.get,
          parameters: { bucket: bucket_name,
                        object: file_path }
        )
      end

      ## Copy a file from source bucket/object to a
      # destination bucket/object.
      def copy_file source_bucket_name, source_file_path,
                    destination_bucket_name, destination_file_path
        @client.execute(
          api_method: @storage.objects.copy,
          parameters: { sourceBucket: source_bucket_name,
                        sourceObject: source_file_path,
                        destinationBucket: destination_bucket_name,
                        destinationObject: destination_file_path }
        )
      end

      ##
      # Download contents of a file.
      def download_file bucket_name, file_path
        @client.execute(
          api_method: @storage.objects.get,
          parameters: { bucket: bucket_name,
                        object: file_path,
                        alt: :media }
        )
      end

      ##
      # Permenently deletes a file.
      def delete_file bucket_name, file_path
        @client.execute(
          api_method: @storage.objects.delete,
          parameters: { bucket: bucket_name,
                        object: file_path }
        )
      end

      ##
      # Retrieves the mime-type for a file path.
      # An empty string is returned if no mime-type can be found.
      def mime_type_for path
        MIME::Types.of(path).first.to_s
      end
    end
  end
end
