defmodule BbhWeb.MCP.Server do
  @moduledoc """
  JSON-RPC dispatch for the MCP endpoint.

  Deliberately a plain function over a decoded message rather than a plug: the whole
  protocol is then testable without a connection, and the controller shrinks to
  transport concerns (status codes, headers, encoding).

  The server is stateless. It hands out no `Mcp-Session-Id` and keeps nothing between
  requests, which the Streamable HTTP transport explicitly permits and which is what lets
  the endpoint cost nothing at rest on a small host.
  """
  alias BbhWeb.MCP
  alias BbhWeb.MCP.Tools

  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602

  @doc """
  Handles one decoded JSON-RPC message.

  Returns `{:reply, response}` for a request, `:accepted` for a notification (the
  transport answers `202` with no body), or `{:error, response}` for a message that is
  not a valid JSON-RPC call at all.
  """
  def handle(message, scope, api_token)

  def handle(%{"jsonrpc" => "2.0", "method" => method} = message, scope, api_token)
      when is_binary(method) do
    id = Map.get(message, "id")

    # A notification carries no id and gets no response, only an acknowledgement.
    if is_nil(id) do
      notification(method)
    else
      {:reply, response(id, dispatch(method, params(message), scope, api_token))}
    end
  end

  # A JSON-RPC *response* from the client (it has an id and a result/error but no method)
  # is acknowledged like a notification. This server never sends requests, so one should
  # not arrive — but answering 202 is the transport's contract for anything id-less.
  def handle(%{"jsonrpc" => "2.0", "result" => _}, _scope, _api_token), do: :accepted
  def handle(%{"jsonrpc" => "2.0", "error" => _}, _scope, _api_token), do: :accepted

  # Batches were removed from the protocol; a list is not a message.
  def handle(messages, _scope, _api_token) when is_list(messages) do
    {:error, error_response(nil, @invalid_request, "Batch requests are not supported.")}
  end

  def handle(_message, _scope, _api_token) do
    {:error, error_response(nil, @invalid_request, ~s(Expected a JSON-RPC 2.0 message.))}
  end

  @doc "Wraps a body that could not be parsed as JSON at all."
  def parse_error, do: error_response(nil, @parse_error, "Request body is not valid JSON.")

  defp notification("notifications/" <> _rest), do: :accepted
  # An unknown id-less method is still a notification: there is nobody to answer.
  defp notification(_method), do: :accepted

  defp params(%{"params" => params}) when is_map(params), do: params
  defp params(_message), do: %{}

  ## Methods

  defp dispatch("initialize", params, _scope, _api_token) do
    {:ok,
     %{
       protocolVersion: negotiate(params["protocolVersion"]),
       capabilities: %{tools: %{listChanged: false}},
       serverInfo: %{name: "buterland-beckerhook", version: version()},
       instructions: instructions()
     }}
  end

  defp dispatch("ping", _params, _scope, _api_token), do: {:ok, %{}}

  defp dispatch("tools/list", _params, scope, api_token) do
    {:ok, %{tools: Tools.list_for(scope, api_token)}}
  end

  defp dispatch("tools/call", params, scope, api_token) do
    case params do
      %{"name" => name} when is_binary(name) ->
        case Tools.call(name, Map.get(params, "arguments", %{}), scope, api_token) do
          {:ok, result} -> {:ok, result}
          {:error, :unknown_tool} -> {:error, @invalid_params, ~s(Unknown tool "#{name}".)}
        end

      _ ->
        {:error, @invalid_params, ~s(tools/call requires a "name".)}
    end
  end

  defp dispatch(method, _params, _scope, _api_token) do
    {:error, @method_not_found, ~s(Unknown method "#{method}".)}
  end

  # Echo the client's revision when we speak it, otherwise name ours and let the client
  # decide whether it can live with that — which is what the lifecycle spec prescribes.
  defp negotiate(requested) do
    if requested in MCP.supported_versions(),
      do: requested,
      else: MCP.preferred_version()
  end

  defp version do
    case :application.get_key(:bbh, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _ -> "0.0.0"
    end
  end

  # Shown to the model once, at connect time. Worth its length: it is the difference
  # between an assistant that files a tidy draft and one that publishes a push
  # notification to the whole club by accident.
  defp instructions do
    """
    Content management for buterland-beckerhook.de, the website of a German
    Schützenverein. All stored content is German — write titles and article text in
    German unless told otherwise.

    An article is a shell (title, slug, date, hero image) plus an ordered list of content
    blocks. Creating one is therefore two steps: create_article, then add_article_block
    with type "richtext" for the text. Block bodies are Markdown.

    New articles are drafts. Publishing sends a push notification to every subscriber, so
    never set status "published" on your own initiative — leave it to the user.

    Nothing here can delete or upload. Images must already exist in the media library;
    find them with search_media and attach them by id.
    """
  end

  ## Envelopes

  defp response(id, {:ok, result}), do: %{jsonrpc: "2.0", id: id, result: result}

  defp response(id, {:error, code, message}), do: error_response(id, code, message)

  defp error_response(id, code, message) do
    %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
  end
end
