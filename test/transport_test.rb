require 'helper'

require 'ddtrace/transport'
require 'ddtrace/encoding'

class UtilsTest < Minitest::Test
  def setup
    # set the transport and temporary disable the logger to prevent
    # spam in the tests output
    @default_transport = Datadog::HTTPTransport.new('localhost', '8126')
    @transport_json = Datadog::HTTPTransport.new('localhost', '8126', encoder: Datadog::Encoding::JSONEncoder.new())
    @transport_msgpack = Datadog::HTTPTransport.new('localhost', '8126', encoder: Datadog::Encoding::MsgpackEncoder.new())
    @original_level = Datadog::Tracer.log.level
    Datadog::Tracer.log.level = Logger::FATAL
  end

  def teardown
    # set the original log level
    Datadog::Tracer.log.level = @original_level
  end

  def test_handle_response
    # a response must be handled as expected
    response = Net::HTTPResponse.new(1.0, 200, 'OK')
    @default_transport.handle_response(response)
    assert true
  end

  def test_handle_response_nil
    # a nil answer should not crash the thread
    @default_transport.handle_response(nil)
    assert true
  end

  def test_send_traces
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    traces = get_test_traces(2)

    # JSON encoding
    code = @transport_json.send(:traces, traces)
    assert_equal true, @transport_json.success?(code), "transport.send failed, code: #{code}"

    # Msgpack encoding
    code = @transport_msgpack.send(:traces, traces)
    assert_equal true, @transport_msgpack.success?(code), "transport.send failed, code: #{code}"
  end

  def test_agent_decodes_float_metrics
    # test that the agent can decoder properly our metrics
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    # one trace with two spans
    traces = get_test_traces(2)

    # set some metrics to the trace
    traces[0][0].set_metric('a', 10.0)
    traces[0][1].set_metric('b', 1231543543265475686787869123.0)

    # JSON encoding
    code = @transport_json.send(:traces, traces)
    assert_equal true, @transport_json.success?(code), "transport.send failed, code: #{code}"

    # Msgpack encoding
    code = @transport_msgpack.send(:traces, traces)
    assert_equal true, @transport_msgpack.success?(code), "transport.send failed, code: #{code}"
  end

  def test_send_services
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    services = get_test_services()

    # JSON encoding
    code = @transport_json.send(:services, services)
    assert_equal true, @transport_json.success?(code), "transport.send failed, code: #{code}"

    # Msgpack encoding
    code = @transport_msgpack.send(:services, services)
    assert_equal true, @transport_msgpack.success?(code), "transport.send failed, code: #{code}"
  end

  def test_send_server_error
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    bad_transport = Datadog::HTTPTransport.new('localhost', '8888')
    traces = get_test_traces(2)
    code = bad_transport.send(:traces, traces)
    assert_equal true, bad_transport.server_error?(code),
                 "transport.send did not fail (it should have failed) code: #{code}"
  end

  def test_send_router
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent
    traces = get_test_traces(2)

    code = @default_transport.send(:admin, traces)
    assert_nil code, "transport.send did not return 'nil'; code: #{code}"
  end

  def test_traces_api_downgrade
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent
    traces = get_test_traces(2)

    # defaults should use the Msgpack encoder
    assert_equal true, @default_transport.encoder.is_a?(Datadog::Encoding::MsgpackEncoder),
                 "transport doesn't use Msgpack encoder, found: #{@default_transport.encoder}"

    assert_equal 'application/msgpack', @default_transport.headers['Content-Type'],
                 "transport content-type is not msgpack, found: #{@default_transport.headers['Content-Type']}"

    post = proc do |url, *rest|
      return 404 unless url.start_with?('/v0.2')
      @default_transport.post(url, *rest)
    end

    code = @default_transport.stub(:post, post) do
      @default_transport.send(:traces, traces)
    end

    # HTTPTransport should downgrade the encoder and API level
    assert_equal true, @default_transport.encoder.is_a?(Datadog::Encoding::JSONEncoder),
                 "transport didn't downgrade the encoder, found: #{@default_transport.encoder}"
    assert_equal 'application/json', @default_transport.headers['Content-Type'],
                 "transport content-type is not json, found: #{@default_transport.headers['Content-Type']}"

    # in any cases, the call should end with a success
    assert_equal true, @default_transport.success?(code), "transport.send failed, code: #{code}"
  end

  def test_services_api_downgrade
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent
    services = get_test_services()

    # defaults should use the Msgpack encoder
    assert_equal true, @default_transport.encoder.is_a?(Datadog::Encoding::MsgpackEncoder),
                 "transport doesn't use Msgpack encoder, found: #{@default_transport.encoder}"

    assert_equal 'application/msgpack', @default_transport.headers['Content-Type'],
                 "transport content-type is not msgpack, found: #{@default_transport.headers['Content-Type']}"

    post = proc do |url, *rest|
      return 404 unless url.start_with?('/v0.2')
      @default_transport.post(url, *rest)
    end

    code = @default_transport.stub(:post, post) do
      @default_transport.send(:services, services)
    end

    # HTTPTransport should downgrade the encoder and API level
    assert_equal true, @default_transport.encoder.is_a?(Datadog::Encoding::JSONEncoder),
                 "transport didn't downgrade the encoder, found: #{@default_transport.encoder}"
    assert_equal 'application/json', @default_transport.headers['Content-Type'],
                 "transport content-type is not json, found: #{@default_transport.headers['Content-Type']}"

    # in any cases, the call should end with a success
    assert_equal true, @default_transport.success?(code), "transport.send failed, code: #{code}"
  end
end
