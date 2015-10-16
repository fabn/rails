require 'helper'
require 'active_job/arguments'
require 'models/person'
require 'active_support/core_ext/hash/indifferent_access'
require 'jobs/kwargs_job'
require 'minitest/mock'

class ArgumentSerializationTest < ActiveSupport::TestCase
  setup do
    @person = Person.find('5')
  end

  [ nil, 1, 1.0, 1_000_000_000_000_000_000_000,
    'a', true, false,
    [ 1, 'a' ],
    { 'a' => 1 }
  ].each do |arg|
    test "serializes #{arg.class} verbatim" do
      assert_arguments_unchanged arg
    end
  end

  [ :a, Object.new, self, Person.find('5').to_gid ].each do |arg|
    test "does not serialize #{arg.class}" do
      assert_raises ActiveJob::SerializationError do
        ActiveJob::Arguments.serialize [ arg ]
      end

      assert_raises ActiveJob::DeserializationError do
        ActiveJob::Arguments.deserialize [ arg ]
      end
    end
  end

  test 'should convert records to Global IDs' do
    assert_arguments_roundtrip [@person]
  end

  test 'should dive deep into arrays and hashes' do
    assert_arguments_roundtrip [3, [@person]]
    assert_arguments_roundtrip [{ 'a' => @person }]
  end

  test 'should maintain string and symbol keys' do
    assert_arguments_roundtrip([a: 1, "b" => 2])
  end

  test 'should maintain hash with indifferent access' do
    symbol_key = { a: 1 }
    string_key = { 'a' => 1 }
    indifferent_access = { a: 1 }.with_indifferent_access

    assert_not_instance_of ActiveSupport::HashWithIndifferentAccess, perform_round_trip([symbol_key]).first
    assert_not_instance_of ActiveSupport::HashWithIndifferentAccess, perform_round_trip([string_key]).first
    assert_instance_of ActiveSupport::HashWithIndifferentAccess, perform_round_trip([indifferent_access]).first
  end

  # Used in the following test, this will work out of the box because only uses basic types
  CustomType = Struct.new('CustomType', :foo, :bar) do
    include ActiveJob::Serialization
  end

  test 'should use custom serialization when implemented' do
    value = CustomType.new(rand(1000), rand(1000))
    assert_arguments_roundtrip [value]
  end

  # This class has an Object instance variable, thus it won't be accepted by YAML.safe_load
  class ComplexType
    include ActiveJob::Serialization
    def initialize
      @x = Object.new
    end
  end

  test 'should disallow types rejected by YAML.safe_load default configuration' do
    assert_raises ActiveJob::DeserializationError do
      perform_round_trip [ComplexType.new]
    end
  end

  test 'should raise when YAML does not support safe_load' do
    ::YAML.stub :respond_to?, false do
      assert_raises NotImplementedError, 'To use automatic unserialization your YAML library must support #safe_load' do
        perform_round_trip [ComplexType.new]
      end
    end
  end

  test 'should disallow non-string/symbol hash keys' do
    assert_raises ActiveJob::SerializationError do
      ActiveJob::Arguments.serialize [ { 1 => 2 } ]
    end

    assert_raises ActiveJob::SerializationError do
      ActiveJob::Arguments.serialize [ { :a => [{ 2 => 3 }] } ]
    end

    assert_raises ActiveJob::SerializationError do
      ActiveJob::Arguments.serialize [ '_aj_globalid' => 1 ]
    end

    assert_raises ActiveJob::SerializationError do
      ActiveJob::Arguments.serialize [ :_aj_globalid => 1 ]
    end
  end

  test 'should not allow non-primitive objects' do
    assert_raises ActiveJob::SerializationError do
      ActiveJob::Arguments.serialize [Object.new]
    end

    assert_raises ActiveJob::SerializationError do
      ActiveJob::Arguments.serialize [1, [Object.new]]
    end
  end

  test 'allows for keyword arguments' do
    KwargsJob.perform_later(argument: 2)

    assert_equal "Job with argument: 2", JobBuffer.last_value
  end

  test 'raises a friendly SerializationError for records without ids' do
    err = assert_raises ActiveJob::SerializationError do
      ActiveJob::Arguments.serialize [Person.new(nil)]
    end
    assert_match 'Unable to serialize Person without an id.', err.message
  end

  private
    def assert_arguments_unchanged(*args)
      assert_arguments_roundtrip args
    end

    def assert_arguments_roundtrip(args)
      assert_equal args, perform_round_trip(args)
    end

    def perform_round_trip(args)
      ActiveJob::Arguments.deserialize(ActiveJob::Arguments.serialize(args))
    end
end
