# frozen_string_literal: true

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


require "bigtable_helper"

describe "Instance Tables", :bigtable do
  let(:instance_id) { bigtable_instance_id }

  it "create, list all, get table and delete table" do
    table_id = "test-table-#{random_str}"

    table = bigtable.create_table(instance_id, table_id) do |cfs|
      cfs.add("cf", gc_rule: Google::Cloud::Bigtable::GcRule.max_versions(3))
    end

    table.must_be_kind_of Google::Cloud::Bigtable::Table

    tables = bigtable.tables(instance_id).to_a
    tables.wont_be :empty?
    tables.each do |t|
      t.must_be_kind_of Google::Cloud::Bigtable::Table
    end

    table = bigtable.table(instance_id, table_id, perform_lookup: true)
    table.must_be_kind_of Google::Cloud::Bigtable::Table

    table.delete
    table.exists?.must_equal false
  end

  it "create table with initial splits and granularity" do
    table_id = "test-table-#{random_str}"
    initial_splits = ["customer-001", "customer-005", "customer-010"]

    table = bigtable.create_table(
        instance_id,
        table_id,
        initial_splits: initial_splits,
        granularity: :MILLIS) do |cfs|
      cfs.add("cf", gc_rule: Google::Cloud::Bigtable::GcRule.max_versions(1))
    end

    table.must_be_kind_of Google::Cloud::Bigtable::Table
    table.granularity_millis?.must_equal true
    table.exists?.must_equal true

    entries = 10.times.map do |i|
      key = "customer-#{"%03d" % (i+1).to_s}"
      table.new_mutation_entry(key).set_cell("cf", "field1", "v-#{i+1}")
    end

    table.mutate_rows(entries)
    sample_keys = table.sample_row_keys.to_a.map(&:key)

    initial_splits.each do |key|
      sample_keys.must_include(key)
    end

    table.delete
  end

  it "creates a table with column families" do
    table_id = "test-table-#{random_str}"

    table = bigtable.create_table(instance_id, table_id) do |cfs|
      cfs.add("cf1") # default service value for GcRule
      cfs.add("cf2", gc_rule: Google::Cloud::Bigtable::GcRule.max_versions(5))
      cfs.add("cf3", gc_rule: Google::Cloud::Bigtable::GcRule.max_age(600))
    end

    column_families = table.column_families
    column_families.must_be_kind_of Google::Cloud::Bigtable::ColumnFamilyMap
    column_families.must_be :frozen?
    column_families.count.must_equal 3

    cf1 = column_families["cf1"]
    cf1.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf1.gc_rule.must_be :nil?

    cf2 = column_families["cf2"]
    cf2.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf2.gc_rule.max_versions.must_equal 5

    cf3 = column_families["cf3"]
    cf3.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf3.gc_rule.max_age.must_equal 600

    table.delete
  end

  describe "replication consistency" do
    let(:table) { bigtable_read_table }

    it "generate consistency token and check consistency" do
      token = table.generate_consistency_token
      token.wont_be :nil?
      result = table.check_consistency(token)
      [true, false].must_include result
    end

    it "generate consistency token and check consistency wail unitil complete" do
      result = table.wait_for_replication(timeout: 600, check_interval: 3)
      [true, false].must_include result
    end
  end
end
