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

describe Google::Cloud::Bigtable::Table, :column_families, :bigtable do
  let(:instance_id) { bigtable_instance_id }
  let(:table_id) { "test-table-#{random_str}" }
  let(:table){
    add_table_to_cleanup_list(table_id)

    bigtable.create_table(instance_id, table_id) do |cfs|
      cfs.add('cf1', gc_rule: Google::Cloud::Bigtable::GcRule.max_age(600))
      cfs.add('cf2', gc_rule: Google::Cloud::Bigtable::GcRule.max_versions(1))
    end
  }

  it "lists column families" do
    gc_rule = Google::Cloud::Bigtable::GcRule.max_versions(1)

    column_families = table.column_families do |cfs|
      cfs.add "cfcreate", gc_rule: gc_rule
    end

    cf = column_families["cfcreate"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfcreate"
    cf.gc_rule.wont_be :nil?
    cf.gc_rule.max_versions.must_equal 1

    cf = table.column_families["cfcreate"] # was updated by table.column_families
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfcreate"
    cf.gc_rule.wont_be :nil?
    cf.gc_rule.max_versions.must_equal 1
  end

  it "adds a column family" do
    gc_rule = Google::Cloud::Bigtable::GcRule.max_versions(1)

    column_families = table.column_families do |cfs|
      cfs.add "cfcreate", gc_rule: gc_rule
    end

    cf = column_families["cfcreate"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfcreate"
    cf.gc_rule.wont_be :nil?
    cf.gc_rule.max_versions.must_equal 1

    cf = table.column_families["cfcreate"] # was updated by table.column_families
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfcreate"
    cf.gc_rule.wont_be :nil?
    cf.gc_rule.max_versions.must_equal 1
  end

  it "adds a column family without gc_rule" do
    column_families = table.column_families do |cfs|
      cfs.add "cfcreate"
    end

    cf = column_families["cfcreate"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfcreate"
    cf.gc_rule.must_be :nil?

    cf = table.column_families["cfcreate"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfcreate"
    cf.gc_rule.must_be :nil?
  end

  it "updates a column family" do
    gc_rule = Google::Cloud::Bigtable::GcRule.max_age(300)

    column_families = table.column_families do |cfs|
      cfs.update "cf1", gc_rule: gc_rule
    end

    cf = column_families["cf1"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.gc_rule.max_age.must_equal 300

    cf = table.column_families["cf1"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.gc_rule.max_age.must_equal 300
  end

  it "updates a column family without gc_rule" do
    cf = table.column_families["cf1"]
    cf.gc_rule.wont_be :nil?

    column_families = table.column_families do |cfs|
      cfs.update "cf1"
    end

    cf = column_families["cf1"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.gc_rule.must_be :nil?

    cf = table.column_families["cf1"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.gc_rule.must_be :nil?
  end

  it "deletes a column family" do
    table.column_families["cf2"].wont_be :nil?

    column_families = table.column_families do |cfs|
      cfs.delete "cf2"
    end

    column_families["cf2"].must_be :nil?
    table.column_families["cf2"].must_be :nil?
  end

  it "adds a column family with union gc rules" do
    gc_rule_1 = Google::Cloud::Bigtable::GcRule.max_versions(3)
    gc_rule_2 = Google::Cloud::Bigtable::GcRule.max_age(300)
    gc_union_rule = Google::Cloud::Bigtable::GcRule.union(gc_rule_1, gc_rule_2)

    column_families = table.column_families do |cfs|
      cfs.add "cfunion", gc_rule: gc_union_rule
    end

    cf = column_families["cfunion"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfunion"
    rules = cf.gc_rule.union
    rules.must_be_kind_of Array
    rules.count.must_equal 2
    rules[0].must_be_kind_of Google::Cloud::Bigtable::GcRule
    rules[0].max_versions.must_equal 3
    rules[1].must_be_kind_of Google::Cloud::Bigtable::GcRule
    rules[1].max_age.must_equal 300

    cf = table.column_families["cfunion"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfunion"
    cf.gc_rule.union.count.must_equal 2
  end

  it "adds a column family with intersection gc rules" do
    gc_rule_1 = Google::Cloud::Bigtable::GcRule.max_versions(1)
    gc_rule_2 = Google::Cloud::Bigtable::GcRule.max_age(600)
    gc_intersection_rule = Google::Cloud::Bigtable::GcRule.intersection(
      gc_rule_1, gc_rule_2
    )

    column_families = table.column_families do |cfs|
      cfs.add "cfintersect", gc_rule: gc_intersection_rule
    end

    cf = column_families["cfintersect"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfintersect"
    rules = cf.gc_rule.intersection
    rules.must_be_kind_of Array
    rules.count.must_equal 2
    rules[0].must_be_kind_of Google::Cloud::Bigtable::GcRule
    rules[0].max_versions.must_equal 1
    rules[1].must_be_kind_of Google::Cloud::Bigtable::GcRule
    rules[1].max_age.must_equal 600

    cf = table.column_families["cfintersect"]
    cf.must_be_kind_of Google::Cloud::Bigtable::ColumnFamily
    cf.name.must_equal "cfintersect"
    cf.gc_rule.intersection.count.must_equal 2
  end
end
