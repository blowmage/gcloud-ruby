# Copyright 2015 Google Inc. All rights reserved.
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

require "helper"
require "json"
require "uri"

describe Gcloud::Bigquery::Table, :mock_bigquery do
  let(:dataset) { "my_dataset" }
  let(:table_id) { "my_table" }
  let(:table_name) { "My Table" }
  let(:description) { "This is my table" }
  let(:etag) { "etag123456789" }
  let(:location_code) { "US" }
  let(:api_url) { "http://googleapi/bigquery/v2/projects/#{project}/datasets/#{dataset}/tables/#{table_id}" }
  let(:table_hash) { random_table_hash dataset, table_id, table_name, description }
  let(:table_gapi) { Google::Apis::BigqueryV2::Table.from_json table_hash.to_json }
  let(:table) { Gcloud::Bigquery::Table.from_gapi table_gapi, bigquery.service }

  it "knows its attributes" do
    table.name.must_equal table_name
    table.description.must_equal description
    table.etag.must_equal etag
    table.api_url.must_equal api_url
    table.bytes_count.must_equal 1000
    table.rows_count.must_equal 100
    table.table?.must_equal true
    table.view?.must_equal false
    table.location.must_equal location_code
  end

  it "knows its fully-qualified ID" do
    table.id.must_equal "#{project}:#{dataset}.#{table_id}"
  end

  it "knows its fully-qualified query ID" do
    table.query_id.must_equal "[#{project}:#{dataset}.#{table_id}]"
  end

  it "knows its creation and modification and expiration times" do
    now = Time.now
    table_hash["creationTime"] = (now.to_f * 1000).floor
    table_hash["lastModifiedTime"] = (now.to_f * 1000).floor
    table_hash["expirationTime"] = (now.to_f * 1000).floor


    table.created_at.must_be_close_to now
    table.modified_at.must_be_close_to now
    table.expires_at.must_be_close_to now
  end

  it "can have an empty expiration times" do
    table_hash["expirationTime"] = nil

    table.expires_at.must_be :nil?
  end

  it "knows schema, fields, and headers" do
    table.schema.must_be_kind_of Gcloud::Bigquery::Schema
    table.schema.must_be :frozen?
    table.fields.map(&:name).must_equal table.schema.fields.map(&:name)
    table.headers.must_equal ["name", "age", "score", "active"]
  end

  it "can delete itself" do
    mock = Minitest::Mock.new
    mock.expect :delete_table, nil,
      [project, dataset, table_id]
    table.service.mocked_service = mock

    table.delete

    mock.verify
  end

  it "can reload itself" do
    new_description = "New description of the table."

    mock = Minitest::Mock.new
    table_hash = random_table_hash dataset, table_id, table_name, new_description
    mock.expect :get_table, Google::Apis::BigqueryV2::Table.from_json(table_hash.to_json),
      [project, dataset, table_id]
    table.service.mocked_service = mock

    table.description.must_equal description
    table.reload!

    mock.verify

    table.description.must_equal new_description
  end
end
