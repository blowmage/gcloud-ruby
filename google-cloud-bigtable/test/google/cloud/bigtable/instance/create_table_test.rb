# Copyright 2018 Google LLC
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


require "helper"

describe Google::Cloud::Bigtable::Instance, :create_table, :mock_bigtable do
  let(:instance_id) { "test-instance" }
  let(:instance_grpc){
    Google::Bigtable::Admin::V2::Instance.new(name: instance_path(instance_id))
  }
  let(:instance) {
    Google::Cloud::Bigtable::Instance.from_grpc(instance_grpc, bigtable.service)
  }
  let(:table_id) { "new-table" }
  let(:initial_splits) { [ "category-1", "category-2" ] }

  it "creates a table without column family" do
    mock = Minitest::Mock.new

    req_table = Google::Bigtable::Admin::V2::Table.new
    create_res = Google::Bigtable::Admin::V2::Table.new(
      name: table_path(instance_id, table_id)
    )

    mock.expect :create_table, create_res, [
      instance_path(instance_id),
      table_id,
      req_table,
      initial_splits: nil
    ]
    bigtable.service.mocked_tables = mock

    table = instance.create_table(table_id)
    mock.verify

    table.project_id.must_equal project_id
    table.instance_id.must_equal instance_id
    table.name.must_equal table_id
    table.path.must_equal table_path(instance_id, table_id)
  end

  it "creates a table with column families" do
    mock = Minitest::Mock.new
    cluster_states = clusters_state_grpc(num: 1)
    column_families = column_families_grpc num: 1, max_versions: 1

    create_res = Google::Bigtable::Admin::V2::Table.new(
      table_hash(
        name: table_path(instance_id, table_id),
        cluster_states: cluster_states,
        column_families: column_families,
        granularity: :MILLIS
      )
    )

    req_table = Google::Bigtable::Admin::V2::Table.new(
      column_families: column_families,
      granularity: :MILLIS
    )

    mock.expect :create_table, create_res.dup, [
      instance_path(instance_id),
      table_id,
      req_table,
      initial_splits: nil
    ]
    mock.expect :get_table, create_res.dup, [
      table_path(instance_id, table_id),
      view: :REPLICATION_VIEW
    ]
    bigtable.service.mocked_tables = mock

    table = instance.create_table(table_id, granularity: :MILLIS) do |cfs|
      cfs.add('cf1', Google::Cloud::Bigtable::GcRule.max_versions(1))
    end

    table.project_id.must_equal project_id
    table.instance_id.must_equal instance_id
    table.name.must_equal table_id
    table.path.must_equal table_path(instance_id, table_id)
    table.granularity.must_equal :MILLIS
    table.column_families.keys.sort.must_equal column_families.keys
    table.column_families.each do |name, cf|
      cf.gc_rule.to_grpc.must_equal column_families[cf.name].gc_rule
    end
    table.cluster_states.map(&:cluster_name).sort.must_equal cluster_states.keys

    mock.verify
  end

  it "creates a table with initial split keys" do
    mock = Minitest::Mock.new
    column_families = column_families_grpc num: 1, max_versions: 1

    create_res = Google::Bigtable::Admin::V2::Table.new(
      table_hash(
        name: table_path(instance_id, table_id),
        column_families: column_families.to_h,
        granularity: :MILLIS
      )
    )

    req_table = Google::Bigtable::Admin::V2::Table.new(
      column_families: column_families.to_h,
      granularity: :MILLIS
    )

    mock.expect :create_table, create_res.dup, [
      instance_path(instance_id),
      table_id,
      req_table,
      initial_splits: initial_splits.map { |key| { key: key } }
    ]
    bigtable.service.mocked_tables = mock

    table = instance.create_table(
      table_id,
      granularity: :MILLIS,
      initial_splits: initial_splits
    ) do |cfs|
      cfs.add('cf1', Google::Cloud::Bigtable::GcRule.max_versions(1))
    end

    table.project_id.must_equal project_id
    table.instance_id.must_equal instance_id
    table.name.must_equal table_id
    table.path.must_equal table_path(instance_id, table_id)
    table.granularity.must_equal :MILLIS
    table.column_families.keys.sort.must_equal column_families.keys
    table.column_families.each do |name, cf|
      cf.gc_rule.to_grpc.must_equal column_families[cf.name].gc_rule
    end

    mock.verify
  end
end
