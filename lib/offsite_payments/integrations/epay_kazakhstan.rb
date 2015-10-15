require 'base64'
require 'openssl'
require 'money'

module OffsitePayments
  module Integrations
    module EpayKazakhstan
      class Configuration
        VALID_OPTIONS_KEYS  = [:merchant_certificate_id, :merchant_name, :private_key_path, :private_key_pass, :public_key_path, :merchant_id]

        attr_accessor(*VALID_OPTIONS_KEYS)

        # Creates a hash of options
        def options
          VALID_OPTIONS_KEYS.reduce({}) do |option, key|
            option.merge!(key => send(key))
          end
        end
      end

      def self.configuration
        @configuration ||= Configuration.new
      end

      def self.configure
        yield(configuration)
      end

      self.production_url = 'http://3dsecure.kkb.kz/jsp/process/logon.jsp'
      self.test_url = 'https://epay.kkb.kz/jsp/process/logon.jsp'

      def self.service_url
        mode = OffsitePayments.mode
        case mode
        when :production
          self.production_url
        when :test
          self.test_url
        else
          raise StandardError, "Integration mode set to an invalid value: #{mode}"
        end
      end

      class MissingKeyFileError < StandardError; end
      class MissingFieldError < StandardError; end

      module Common
        def sign(content)
          raise MissingKeyFileError.new if configuration.private_key_path.blank?
          digest = OpenSSL::Digest::SHA1.new
          pkey = nil
          if configuration.private_key_pass.nil?
            pkey = OpenSSL::PKey::RSA.new(configuration.private_key_path)
          else
            pkey = OpenSSL::PKey::RSA.new(configuration.private_key_path, configuration.private_key_pass)
          end

          pkey.sign(digest, content)
        end

        def sign_base64(content)
          Base64.encode64(sign(content))
        end

        def configuration
          @configuration ||= OffsitePayments::Integrations::EpayKazakhstan.configuration
        end

        def get_currency_iso_numeric(currency_code)
          money = Money.new(100, currency_code)
          if money
            money.currency.iso_numeric
          else
            currency_code
          end
        end
      end

      class Helper < OffsitePayments::Helper
        include Common

        def initialize(order_id, email, amount, currency_code, options = {})
          options.assert_valid_keys(:shop_id, :back_link :failure_back_link, :post_link, :failure_post_link, :language)
          check_mandatory_fields(options)
          @order_id, @email, @amount, @currency_code = order_id, email, amount, currency_code
          options.each_pair { |k, v| self.send(k, v) if v.present? }
          self.signed_order base64_signed_xml
        end

        mapping :shop_id, 'ShopID'
        mapping :email, 'email'
        mapping :back_link, 'BackLink'
        mapping :failure_back_link, 'FailureBackLink'
        mapping :post_link, 'PostLink'
        mapping :failure_post_link, 'FailurePostLink'
        mapping :language, 'Language'
        mapping :signed_order, 'Signed_Order_B64'

        private

        def currency
          @currency ||= get_currency_iso_numeric(@currency_code)
        end

        def order_id
          @order ||= @order_id.to_s.rjust(6, '0')
        end

        def base64_signed_xml
          @signed_xml ||= begin
            hash = {merchant_certificate_id: configuration.merchant_certificate_id, merchant_name: configuration.merchant_name, , merchant_id: configuration.merchant_id
                  order_id: order_id, amount: @amount, currency: currency}
            xml = xml_template % hash
            sign_base64(xml)
          end
        end

        def check_mandatory_fields(options)
          mandatory_fields = [:email, :back_link, :post_link]
          check = mandatory_fields - options.keys
          raise MissingFieldError.new("missing mandatory fields: #{check.join(', ')}") if check.present?
        end

        def xml_template
          '<merchant cert_id="%{merchant_certificate_id}" name="%{merchant_name}"><order order_id="%{order_id}" amount="%{amount}" currency="%{currency}"><department merchant_id="%{merchant_id}" amount="%{amount}"/></order></merchant>'
        end
      end

      class Notification < OffsitePayments::Notification

      end
    end
  end
end