require 'test_helper'

class EpayKazakhstanHelperTest < Test::Unit::TestCase
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

    @helper = EpayKazakhstan::Helper.new(10, 'khai.le@live.com', 10, 'KZT', back_link: 'localhost/back', post_link: 'localhost/post')
  end

  def test_basic_helper_fields
    assert_field 'email', 'khai.le@live.com'
    assert_field 'BackLink', 'localhost/back'
    assert_field 'PostLink', 'localhost/post'
    assert_field 'Signed_Order_B64', "PGRvY3VtZW50PjxtZXJjaGFudCBjZXJ0X2lkPSIwMEMxODJCMTg5IiBuYW1l\nPSJUZXN0IHNob3AiPjxvcmRlciBvcmRlcl9pZD0iMDAwMDEwIiBhbW91bnQ9\nIjEwIiBjdXJyZW5jeT0iMzk4Ij48ZGVwYXJ0bWVudCBtZXJjaGFudF9pZD0i\nOTIwNjExMDEiIGFtb3VudD0iMTAiLz48L29yZGVyPjwvbWVyY2hhbnQ+PG1l\ncmNoYW50X3NpZ24gdHlwZT0iUlNBIj5KUVRBZlUvWHVhMlVUeEYvOXBRa3Fw\nMVZwSSsrRHpsNVVwRWJDVVh6eVZnWklZdERqS09XWDd2ZHlmbU8KS2tSZXpt\nelh5dGlOcmpMMTNRZitCRE9vNUE9PTwvbWVyY2hhbnRfc2lnbj48L2RvY3Vt\nZW50Pg==\n"
  end
end