# frozen_string_literal: true

require 'test_helper'

class HaveAttachedFileMatcherTest < Test::Unit::TestCase
  context "have_attached_file" do
    setup do
      @dummy_class = reset_class "Dummy"
      reset_table "dummies"
      @matcher = self.class.have_attached_file(:avatar)
    end

    should "reject a class with no attachment" do
      assert_rejects @matcher, @dummy_class
    end

    should "accept a class with an attachment" do
      modify_table("dummies") { |d| d.string :avatar_file_name }
      @dummy_class.has_attached_file :avatar
      assert_accepts @matcher, @dummy_class
    end

    should "have messages" do
      assert_equal "have an attachment named avatar", @matcher.description      
      assert_equal "Should have an attachment named avatar", @matcher.failure_message
      assert_equal "Should not have an attachment named avatar", @matcher.negative_failure_message
    end
  end
end
