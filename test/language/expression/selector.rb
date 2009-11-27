#!/usr/bin/env ruby
#
#  Created by Luke A. Kanies on 2006-12-22.
#  Copyright (c) 2006. All rights reserved.

require File.dirname(__FILE__) + '/../../lib/puppettest'

require 'puppettest'
require 'puppettest/parsertesting'

class TestSelector < Test::Unit::TestCase
  include PuppetTest
  include PuppetTest::ParserTesting
  Expression = Puppet::Parser::Expression

  def test_evaluate
    scope = mkscope
    upperparam = nameobj("MYPARAM")
    lowerparam = nameobj("myparam")

    should = {"MYPARAM" => "upper", "myparam" => "lower"}

    maker = Proc.new do
      {
      :default => Expression::ResourceParam.new(:param => Expression::Default.new(:value => "default"), :value => FakeExpression.new("default")),
      :lower => Expression::ResourceParam.new(:param => FakeExpression.new("myparam"), :value => FakeExpression.new("lower")),
      :upper => Expression::ResourceParam.new(:param => FakeExpression.new("MYPARAM"), :value => FakeExpression.new("upper")),
      }

    end

    # Start out case-sensitive
    Puppet[:casesensitive] = true

    %w{MYPARAM myparam}.each do |str|
      param = nameobj(str)
      params = maker.call
      sel = Expression::Selector.new(:param => param, :values => params.values)
      result = nil
      assert_nothing_raised { result = sel.compute_denotation(scope) }
      assert_equal(should[str], result, "did not case-sensitively match #{str}")
    end

    # then insensitive
    Puppet[:casesensitive] = false

    %w{MYPARAM myparam}.each do |str|
      param = nameobj(str)
      params = maker.call

      # Delete the upper value, since we don't want it to match
      # and it introduces a hash-ordering bug in testing.
      params.delete(:upper)
      sel = Expression::Selector.new(:param => param, :values => params.values)
      result = nil
      assert_nothing_raised { result = sel.compute_denotation(scope) }
      assert_equal("lower", result, "did not case-insensitively match #{str}")
    end
  end
end

