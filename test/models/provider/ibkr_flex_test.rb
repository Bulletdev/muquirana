require "test_helper"
require "webmock/minitest"

class Provider::IbkrFlexTest < ActiveSupport::TestCase
  BASE = "https://gdcdyn.interactivebrokers.com".freeze

  setup do
    # poll_interval: 0 evita sleeps reais no teste de polling.
    @client = Provider::IbkrFlex.new(
      query_id: "123456",
      token: "TOKEN",
      base_url: BASE,
      poll_interval: 0,
      max_poll_attempts: 3
    )
    @statement_xml = file_fixture("ibkr/flex_statement.xml").read
  end

  test "requires query_id and token" do
    assert_raises(Provider::IbkrFlex::ConfigurationError) { Provider::IbkrFlex.new(query_id: "", token: "t") }
    assert_raises(Provider::IbkrFlex::ConfigurationError) { Provider::IbkrFlex.new(query_id: "q", token: "") }
  end

  test "SendRequest then GetStatement returns the raw statement XML" do
    stub_send_request(success_reference("REF999"))
    stub_get_statement(@statement_xml)

    body = @client.download_statement

    assert_includes body, "FlexQueryResponse"
    assert_includes body, "AAPL"
  end

  test "polls GetStatement while the statement is still being generated" do
    stub_send_request(success_reference("REF999"))
    # 1a chamada: extrato ainda em geracao (1019). 2a: pronto.
    stub_request(:get, /FlexStatementService\.GetStatement/).to_return(
      { status: 200, body: pending_response("1019") },
      { status: 200, body: @statement_xml }
    )

    body = @client.download_statement
    assert_includes body, "FlexQueryResponse"
  end

  test "raises StatementNotReadyError when still pending after max attempts" do
    stub_send_request(success_reference("REF999"))
    stub_get_statement(pending_response("1019"))

    assert_raises(Provider::IbkrFlex::StatementNotReadyError) { @client.download_statement }
  end

  test "invalid token/query on SendRequest maps to AuthenticationError" do
    stub_send_request(fail_response("1020", "Invalid request or unable to validate request."))

    assert_raises(Provider::IbkrFlex::AuthenticationError) { @client.download_statement }
  end

  test "invalid Flex Query definition maps to InvalidQueryError" do
    stub_send_request(fail_response("1014", "Query is invalid."))

    assert_raises(Provider::IbkrFlex::InvalidQueryError) { @client.download_statement }
  end

  private
    def stub_send_request(body)
      stub_request(:get, /FlexStatementService\.SendRequest/).to_return(status: 200, body: body)
    end

    def stub_get_statement(body)
      stub_request(:get, /FlexStatementService\.GetStatement/).to_return(status: 200, body: body)
    end

    def success_reference(code)
      <<~XML
        <FlexStatementResponse timestamp="18 July, 2026 09:00 AM EDT">
        <Status>Success</Status>
        <ReferenceCode>#{code}</ReferenceCode>
        <Url>#{BASE}/Universal/servlet/FlexStatementService.GetStatement</Url>
        </FlexStatementResponse>
      XML
    end

    def pending_response(code)
      <<~XML
        <FlexStatementResponse timestamp="18 July, 2026 09:00 AM EDT">
        <Status>Warn</Status>
        <ErrorCode>#{code}</ErrorCode>
        <ErrorMessage>Statement generation in progress. Please try again shortly.</ErrorMessage>
        </FlexStatementResponse>
      XML
    end

    def fail_response(code, message)
      <<~XML
        <FlexStatementResponse timestamp="18 July, 2026 09:00 AM EDT">
        <Status>Fail</Status>
        <ErrorCode>#{code}</ErrorCode>
        <ErrorMessage>#{message}</ErrorMessage>
        </FlexStatementResponse>
      XML
    end
end
