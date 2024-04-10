require 'test_helper'

class ValidateAttachmentPresenceMatcherTest < Test::Unit::TestCase
  context "validate_attachment_presence" do
    setup do
      reset_table("dummies"){|d| d.string :avatar_file_name }
      @dummy_class = reset_class "Dummy"
      @dummy_class.has_attached_file :avatar
      @matcher     = self.class.validate_attachment_presence(:avatar)
    end

    should "reject a class with no validation" do
      assert_rejects @matcher, @dummy_class
    end

    should "accept a class with a validation" do
      @dummy_class.validates_attachment_presence :avatar
      assert_accepts @matcher, @dummy_class
    end

    should "have messages" do
      assert_equal "require presence of attachment avatar", @matcher.description      
      assert_equal "Attachment avatar should be required", @matcher.failure_message
      assert_equal "Attachment avatar should not be required", @matcher.negative_failure_message
    end
  end
end
