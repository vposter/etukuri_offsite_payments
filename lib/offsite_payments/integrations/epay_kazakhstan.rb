require 'base64'
require 'openssl'
require 'money'
require 'nokogiri'

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

      def self.notification(post)
        Notification.new(post)
      end

      class MissingKeyFileError < StandardError; end
      class MissingFieldError < StandardError; end

      module Common

        def digest_algorithm_instance
          OpenSSL::Digest::SHA1.new
        end

        def sign(content)
          raise MissingKeyFileError.new if configuration.private_key_path.blank?
          digest = digest_algorithm_instance
          pkey = nil
          if configuration.private_key_pass.nil?
            pkey = OpenSSL::PKey::RSA.new(configuration.private_key_path)
          else
            pkey = OpenSSL::PKey::RSA.new(configuration.private_key_path, configuration.private_key_pass)
          end

          pkey.sign(digest, content)
        end

        def sign_base64(base64_data)
          Base64.encode64(sign(base64_data))
        end

        def configuration
          @configuration ||= OffsitePayments::Integrations::EpayKazakhstan.configuration
        end

        def verify(data, signature)
          digest = digest_algorithm_instance
          pkey = OpenSSL::PKey::RSA.new(configuration.public_key_path)
          pub_key = pkey.public_key
          pub_key.verify(digest, signature, data)
        end

        def verify_base64(data, base64_signature)
          signature = Base64.decode64(base64_signature)
          verify(data, signature)
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
          '<merchant cert_id="%{merchant_certificate_id}" name="%{merchant_name}"><order order_id="%{order_id}" amount="%{amount}" currency="%{currency}"><department merchant_id="%{merchant_id}" amount="%{amount}"/></order></merchant>'.freeze
        end
      end

      class Notification < OffsitePayments::Notification
        Error = Struct.new(:type, :time, :code, :message)
        Customer = Struct.new(:name, :mail, :phone)
        Order = Struct.new(:amount, :currecy, :id)
        Payment = Struct.new(:merchant_id, :amount, :reference, :response_code, :approval_code, :timestamp)

        def has_error?
          @has_error ||= @xml_doc.xpath('//error').any?
        end

        def error
          if has_error?
            @error ||= Error.new.tap do |e|
              error_node = @xml_doc.xpath('//error')
              e.type = error_node.xpath('./@type').to_s
              e.time = DateTime.parse(error_node.xpath('./@time').to_s)
              e.code = error_node.xpath('./@code').to_s
              e.message = error_node.inner_text
            end
          end
        end

        def customer
          unless has_error?
            @customer = Customer.new.tap do |c|
              customer_node = @xml_doc.xpath('//bank/customer')
              c.name = customer_node.xpath('./@name').to_s
              c.mail = customer_node.xpath('./@mail').to_s
              c.phone = customer_node.xpath('./@phone').to_s
            end
          end
        end

        def order
          return @order if @order.present?
          @order = Order.new
          if has_error?
            @order.id = @xml_doc.xpath('//response/@order_id').to_s
          else
            order_node = @xml_doc.xpath('//order')
            @order.id = order_node.xpath('./@order_id').to_s
            @order.amount = order_node.xpath('./@amount').to_s.to_i
            @order.currency = order_node.xpath('./@currency').to_s
          end
          @order
        end

        def payment
          unless has_error?
            @payment ||= Payment.new.tap do |p|
              payment_node = @xml_doc.xpath('//payment')
              p.timestamp = DateTime.parse(payment_node.xpath('../@timestamp').to_s)
              p.amount = payment_node.xpath('./@amount').to_s.to_i
              p.reference = payment_node.xpath('./@reference').to_s
              p.response_code = payment_node.xpath('./@response_code').to_s
              p.approval_code = payment_node.xpath('./@approval_code').to_s
              p.merchant_id = payment_node.xpath('./@merchant_id').to_s
            end
          end
        end

        def bank_name
          @bank_name ||= @xml_doc.xpath('//bank/@name').to_s
        end

        def merchant_name
          @merchant_name ||= @xml_doc.xpath('//merchant/@name').to_s
        end

        def acknowledge
          bank_node = @xml_doc.xpath('//bank').to_s
          signature = @xml_doc.xpath('//bank_sign').inner_text
          verify_base64(bank_node, signature)
        end

        private

        def parse(post)
          @response = post['response']
          @xml_doc = Nokogiri::XML(@response)
        end
      end
    end
  end
end