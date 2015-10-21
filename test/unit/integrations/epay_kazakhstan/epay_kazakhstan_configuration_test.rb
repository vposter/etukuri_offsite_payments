require 'test_helper'

class EpayKazakhstanConfigurationTest < Test::Unit::TestCase
  include OffsitePayments::Integrations

  def setup
    EpayKazakhstan.configure do |config|
      config.merchant_certificate_id = '00C182B189'
      config.merchant_name = 'Test shop'
      config.private_key_pass = 'nissan'
      config.merchant_id = '92061101'
      config.public_key_path = File.expand_path('../kkbca.pem', __FILE__)
      config.private_key_path = File.expand_path('../test_prv.pem', __FILE__)
    end
  end

  def test_configuration
    configuration = EpayKazakhstan.configuration
    assert_equal '00C182B189', configuration.merchant_certificate_id
    assert_equal 'Test shop', configuration.merchant_name
    assert_equal 'nissan', configuration.private_key_pass
    assert_equal '92061101', configuration.merchant_id
    assert_equal true, File.exists?(configuration.public_key_path)
    assert_equal true, File.exists?(configuration.private_key_path)
  end
end