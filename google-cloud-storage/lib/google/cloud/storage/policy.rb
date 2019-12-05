# Copyright 2017 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


require "google/cloud/errors"
require "google/apis/storage_v1"
require "google/cloud/storage/policy/bindings"

module Google
  module Cloud
    module Storage
      ##
      # # Policy
      #
      # Represents a Cloud IAM Policy for the Cloud Storage service.
      #
      # A common pattern for updating a resource's metadata, such as its Policy,
      # is to read the current data from the service, update the data locally,
      # and then send the modified data for writing. This pattern may result in
      # a conflict if two or more processes attempt the sequence simultaneously.
      # IAM solves this problem with the
      # {Google::Cloud::Storage::Policy#etag} property, which is used to
      # verify whether the policy has changed since the last request. When you
      # make a request to with an `etag` value, Cloud IAM compares the `etag`
      # value in the request with the existing `etag` value associated with the
      # policy. It writes the policy only if the `etag` values match.
      #
      # When you update a policy, first read the policy (and its current `etag`)
      # from the service, then modify the policy locally, and then write the
      # modified policy to the service. See
      # {Google::Cloud::Storage::Bucket#policy} and
      # {Google::Cloud::Storage::Bucket#policy=}.
      #
      # @see https://cloud.google.com/iam/docs/managing-policies Managing
      #   policies
      # @see https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy
      #   Buckets: setIamPolicy
      #
      # @attr [String] etag Used to verify whether the policy has changed since
      #   the last request. The policy will be written only if the `etag` values
      #   match.
      # @attr [Integer] version The syntax schema version of the policy. Each version
      #   of the policy contains a specific syntax schema that can be used by bindings.
      #   The newer version may contain role bindings with the newer syntax schema
      #   that is unsupported by earlier versions. This field is not intended to
      #   be used for any purposes other than policy syntax schema control.
      #
      #   The following policy versions are valid:
      #
      #   * 1 -  The first version of Cloud IAM policy schema. Supports binding one
      #     role to one or more members. Does not support conditional bindings.
      #   * 3 - Introduces the condition field in the role binding, which further
      #     constrains the role binding via context-based and attribute-based rules.
      #     See [Conditions Overview](https://cloud.google.com/iam/docs/conditions-overview)
      #     for more information.
      #
      # @example Using Policy version 1:
      #   require "google/cloud/storage"
      #
      #   storage = Google::Cloud::Storage.new
      #   bucket = storage.bucket "my-todo-app"
      #
      #   bucket.policy do |p|
      #     p.version # 1
      #     p.remove "roles/storage.admin", "user:owner@example.com"
      #     p.add "roles/storage.admin", "user:newowner@example.com"
      #     p.roles["roles/storage.objectViewer"] = ["allUsers"]
      #   end
      #
      # @example Updating Policy version 1 to version 3:
      #   require "google/cloud/storage"
      #
      #   storage = Google::Cloud::Storage.new
      #   bucket = storage.bucket "my-todo-app"
      #
      #   bucket.policy do |p|
      #     p.version # 1
      #     p.version = 3
      #     p.bindings.insert({
      #                         role: "roles/storage.admin",
      #                         members: ["user:owner@example.com"],
      #                         condition: {
      #                           title: "test-condition",
      #                           description: "description of condition",
      #                           expression: "expr1"
      #                         }
      #                       })
      #   end
      #
      # @example Using Policy version 3:
      #   require "google/cloud/storage"
      #
      #   storage = Google::Cloud::Storage.new
      #   bucket = storage.bucket "my-todo-app"
      #
      #   bucket.policy(requested_policy_version: 3) do |p|
      #     p.version # 3
      #     p.bindings.insert({
      #                         role: "roles/storage.admin",
      #                         members: ["user:owner@example.com"],
      #                         condition: {
      #                           title: "test-condition",
      #                           description: "description of condition",
      #                           expression: "expr1"
      #                         }
      #                       })
      #   end
      #
      class Policy
        attr_reader :etag
        attr_reader :version

        ##
        # @private Creates a Policy object.
        def initialize etag, version, roles: {}, bindings: []
          @etag = etag
          @version = version
          @roles = roles
          @bindings = Bindings.new
          @bindings.insert(*bindings)
        end

        ##
        # Updates the syntax schema version of the policy. Each version of the
        # policy contains a specific syntax schema that can be used by bindings.
        # The newer version may contain role bindings with the newer syntax schema
        # that is unsupported by earlier versions. This field is not intended to
        # be used for any purposes other than policy syntax schema control.
        #
        # The following policy versions are valid:
        #
        # * 1 -  The first version of Cloud IAM policy schema. Supports binding one
        #   role to one or more members. Does not support conditional bindings.
        # * 3 - Introduces the condition field in the role binding, which further
        #   constrains the role binding via context-based and attribute-based rules.
        #   See [Conditions Overview](https://cloud.google.com/iam/docs/conditions-overview)
        #   for more information.
        #
        # @param [Integer] new_version The syntax schema version of the policy.
        #
        # @see https://cloud.google.com/iam/docs/policies#versions Policy versions
        #
        # @example Updating Policy version 1 to version 3:
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.policy do |p|
        #     p.version # 1
        #     p.version = 3
        #     p.bindings.insert({
        #                         role: "roles/storage.admin",
        #                         members: ["user:owner@example.com"],
        #                         condition: {
        #                           title: "test-condition",
        #                           description: "description of condition",
        #                           expression: "expr1"
        #                         }
        #                       })
        #   end
        #
        def version= new_version
          if new_version < version
            raise "new_version (#{new_version}) cannot be less than the current Policy version (#{version})."
          end
          if version == 1 && new_version > 1
            @roles.freeze
            @bindings.insert(*roles_to_gapi.map(&:to_h))
          end
          @version = new_version
        end

        ##
        # Returns the version 1 bindings as a hash that associates roles with an
        # array of members. See [Understanding
        # Roles](https://cloud.google.com/iam/docs/understanding-roles) for a
        # listing of primitive and curated roles. See [Buckets:
        # setIamPolicy](https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy)
        # for a listing of values and patterns for members.
        #
        # @raise [RuntimeError] If version is greater than 1.
        #
        # @return [Hash{String => Array<String>}] The Policy version 1 bindings.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.policy do |p|
        #     p.version # 1
        #     p.roles["roles/storage.objectViewer"] = ["allUsers"]
        #   end
        #
        def roles
          ensure_version_1
          @roles
        end

        ##
        # Returns the Policy's bindings as an array of hashes that associate roles with an
        # array of members. Conditions are allowed in the hashes. See [Understanding
        # Roles](https://cloud.google.com/iam/docs/understanding-roles) for a
        # listing of primitive and curated roles. See [Buckets:
        # setIamPolicy](https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy)
        # for a listing of values and patterns for members.
        #
        # @raise [RuntimeError] If version is 1.
        #
        # @return [Array<Hash>] The Policy bindings.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.policy(requested_policy_version: 3) do |p|
        #     p.version # 3
        #     p.bindings.insert({
        #                         role: "roles/storage.admin",
        #                         members: ["user:owner@example.com"],
        #                         condition: {
        #                           title: "test-condition",
        #                           description: "description of condition",
        #                           expression: "expr1"
        #                         }
        #                       })
        #   end
        #
        def bindings
          raise "Illegal operation for version 1. Use #roles instead." if version == 1
          @bindings
        end

        def binding role:, members:, condition: nil
          Binding.new role: role, members: members, condition: condition
        end

        ##
        # Convenience method for adding a member to a binding on this policy.
        # See [Understanding
        # Roles](https://cloud.google.com/iam/docs/understanding-roles) for a
        # listing of primitive and curated roles. See [Buckets:
        # setIamPolicy](https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy)
        # for a listing of values and patterns for members.
        #
        # @param [String] role_name A Cloud IAM role, such as
        #   `"roles/storage.admin"`.
        # @param [String] member A Cloud IAM identity, such as
        #   `"user:owner@example.com"`.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.policy do |p|
        #     p.add "roles/storage.admin", "user:newowner@example.com"
        #   end
        #
        def add role_name, member
          ensure_version_1
          role(role_name) << member
        end

        ##
        # Convenience method for removing a member from a binding on this
        # policy. See [Understanding
        # Roles](https://cloud.google.com/iam/docs/understanding-roles) for a
        # listing of primitive and curated roles. See [Buckets:
        # setIamPolicy](https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy)
        # for a listing of values and patterns for members.
        #
        # @param [String] role_name A Cloud IAM role, such as
        #   `"roles/storage.admin"`.
        # @param [String] member A Cloud IAM identity, such as
        #   `"user:owner@example.com"`.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.policy do |p|
        #     p.remove "roles/storage.admin", "user:owner@example.com"
        #   end
        #
        def remove role_name, member
          ensure_version_1
          role(role_name).delete member
        end

        ##
        # Convenience method returning the array of members bound to a role in
        # this policy, or an empty array if no value is present for the role in
        # {#roles}. See [Understanding
        # Roles](https://cloud.google.com/iam/docs/understanding-roles) for a
        # listing of primitive and curated roles. See [Buckets:
        # setIamPolicy](https://cloud.google.com/storage/docs/json_api/v1/buckets/setIamPolicy)
        # for a listing of values and patterns for members.
        #
        # @return [Array<String>] The members strings, or an empty array.
        #
        # @example
        #   require "google/cloud/storage"
        #
        #   storage = Google::Cloud::Storage.new
        #
        #   bucket = storage.bucket "my-todo-app"
        #
        #   bucket.policy do |p|
        #     p.role("roles/storage.admin") << "user:owner@example.com"
        #   end
        #
        def role role_name
          ensure_version_1
          roles[role_name] ||= []
        end

        ##
        # Returns a deep copy of the policy.
        #
        # @deprecated Because the latest policy is now always retrieved by
        #   {Bucket#policy}.
        #
        # @return [Policy]
        #
        def deep_dup
          ensure_version_1
          warn "DEPRECATED: Storage::Policy#deep_dup"
          dup.tap do |p|
            roles_dup = p.roles.each_with_object({}) do |(k, v), memo|
              memo[k] = v.dup rescue value
            end
            p.instance_variable_set :@roles, roles_dup
          end
        end

        ##
        # @private Convert the Policy to a
        # Google::Apis::StorageV1::Policy.
        def to_gapi
          bindings_gapi = version > 1 ? bindings.to_gapi : roles_to_gapi
          Google::Apis::StorageV1::Policy.new(
            etag: etag,
            version: version,
            bindings: bindings_gapi
          )
        end

        ##
        # @private New Policy from a
        # Google::Apis::StorageV1::Policy object.
        def self.from_gapi gapi
          if gapi.version == 1
            roles = Array(gapi.bindings).each_with_object({}) do |binding, memo|
              memo[binding.role] = binding.members.to_a
            end
            new gapi.etag, gapi.version, roles: roles
          else
            new gapi.etag, gapi.version, bindings: Array(gapi.bindings).map(&:to_h)
          end
        end

        protected

        def ensure_version_1
          raise "Illegal operation for Policy version > 1. Use Policy#bindings instead." if version > 1
        end

        def roles_to_gapi
          roles.keys.map do |role_name|
            next if roles[role_name].empty?
            Google::Apis::StorageV1::Policy::Binding.new(
              role: role_name,
              members: roles[role_name].uniq
            )
          end
        end
      end
    end
  end
end
