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

describe Google::Cloud::Bigtable::Project, :modify_column_families, :mock_bigtable do
  let(:instance_id) { "test-instance" }
  let(:table_id) { "test-table" }

  it "modify column families in table" do
    modifications = []
    modifications << Google::Cloud::Bigtable::ColumnFamily.create_modification(
      "cf1", Google::Cloud::Bigtable::GcRule.max_age(600)
    )

    modifications << Google::Cloud::Bigtable::ColumnFamily.update_modification(
      "cf2", Google::Cloud::Bigtable::GcRule.max_versions(5)
    )

    column_families = Google::Cloud::Bigtable::Table::ColumnFamilyMap.new(bigtable.service, instance_id, table_id).tap do |cfs|
      cfs.add('cf1', Google::Cloud::Bigtable::GcRule.max_age(300))
      cfs.add('cf2') # service default GcRule
    end
    cluster_states = clusters_state_grpc(num: 1)
    res_table = Google::Bigtable::Admin::V2::Table.new(
      table_hash(
        name: table_path(instance_id, table_id),
        cluster_states: cluster_states,
        column_families: column_families.to_grpc,
        granularity: :MILLIS
      )
    )

    mock = Minitest::Mock.new
    mock.expect :modify_column_families, res_table, [
      table_path(instance_id, table_id),
      modifications
    ]
    bigtable.service.mocked_tables = mock
    table = bigtable.modify_column_families(instance_id, table_id, modifications)

    mock.verify

    table.project_id.must_equal project_id
    table.instance_id.must_equal instance_id
    table.name.must_equal table_id
    table.path.must_equal table_path(instance_id, table_id)
    table.granularity.must_equal :MILLIS

    cfm = table.column_families
    cfm.class.must_equal Google::Cloud::Bigtable::Table::ColumnFamilyMap
    cfm.must_be_kind_of Hash
    cfm.must_be :frozen?
    cfm.keys.sort.must_equal column_families.keys
    cfm["cf1"].gc_rule.to_grpc.must_equal Google::Cloud::Bigtable::GcRule.max_age(300).to_grpc
    cfm["cf2"].gc_rule.must_be :nil?
  end

  it "modify single column family in table" do
    modification = Google::Cloud::Bigtable::ColumnFamily.create_modification(
      "cf1", Google::Cloud::Bigtable::GcRule.max_age(600)
    )

    column_families = Google::Cloud::Bigtable::Table::ColumnFamilyMap.new(bigtable.service, instance_id, table_id).tap do |cfs|
      cfs.add('cf1', Google::Cloud::Bigtable::GcRule.max_age(600))
    end
    res_table = Google::Bigtable::Admin::V2::Table.new(
      table_hash(
        name: table_path(instance_id, table_id),
        column_families: column_families.to_grpc
      )
    )

    mock = Minitest::Mock.new
    mock.expect :modify_column_families, res_table, [
      table_path(instance_id, table_id),
      [modification]
    ]
    bigtable.service.mocked_tables = mock
    table = bigtable.modify_column_families(instance_id, table_id, modification)

    mock.verify

    table.column_families.keys.sort.must_equal column_families.keys
    table.column_families.each do |name, cf|
      cf.gc_rule.to_grpc.must_equal column_families[cf.name].gc_rule.to_grpc
    end
  end
end
