if Code.ensure_loaded?(AshJsonApi.Error) do
  defmodule AshGettext.JsonApi do
    @moduledoc """
    Translates the `detail` of every error in a JSON:API reply. Installed on the
    domain's `error_handler` for you; you never call it.

    Notes for maintainers: maintainers/why-some-errors-are-hard.md in the repository.
    """

    @serving {__MODULE__, :request}
    @request [:plug, :router_dispatch]

    @doc false
    def remember_request_actors do
      :telemetry.attach_many(
        __MODULE__,
        [@request ++ [:start], @request ++ [:stop], @request ++ [:exception]],
        &__MODULE__.handle_request/4,
        nil
      )
    end

    @doc false
    def handle_request([:plug, :router_dispatch, :start], _measurements, %{conn: conn}, _config),
      do: Process.put(@serving, %{actor: Ash.PlugHelpers.get_actor(conn)})

    def handle_request(_request_ended, _measurements, _metadata, _config),
      do: Process.delete(@serving)

    @doc "The actor of the request this process is serving, or `nil`."
    @spec request_actor() :: term()
    def request_actor, do: Process.get(@serving)[:actor]

    @doc false
    def remember_refusal(%Ash.Error.Forbidden.Policy{} = policy) do
      with %{} = request <- Process.get(@serving) do
        own = Keyword.get(List.wrap(policy.vars), :policy_message, policy.custom_message)

        messages = Map.put(request[:policy_messages] || %{}, policy.resource, own)

        Process.put(@serving, Map.put(request, :policy_messages, messages))
      end
    end

    def remember_refusal(%{errors: errors}) when is_list(errors),
      do: Enum.each(errors, &remember_refusal/1)

    def remember_refusal(_error), do: :ok

    defp carried(%{code: "forbidden"}, resource),
      do: %{policy_message: Process.get(@serving)[:policy_messages][resource]}

    defp carried(%{meta: meta}, _resource) when is_map(meta), do: meta
    defp carried(_error, _resource), do: %{}

    @doc """
    Translate `error`'s `detail` into the language of the request's actor.

    The rules are `AshGettext.TransportText`'s: the `detail` is looked up as
    a msgid, with `meta` as its values, then the written sentence for the
    error's `code`. With neither, the error comes back unchanged.
    """
    @spec translate_error(term(), map()) :: term()
    def translate_error(%AshJsonApi.Error{} = error, %{domain: domain} = context) do
      %{
        error
        | detail:
            AshGettext.TransportText.translate(error.detail, domain,
              code: error.code,
              bindings: Map.put(carried(error, context[:resource]), :id, error.id),
              actor: request_actor(),
              remember_in: @serving
            )
      }
    end

    def translate_error(error, _context), do: error

    @doc """
    Run the app's own `error_handler`, then translate the error it returns.
    """
    @spec translate_error(term(), map(), {module(), atom(), [term()]}) :: term()
    def translate_error(error, context, {module, function, arguments}) do
      module
      |> apply(function, [error, context | arguments])
      |> translate_error(context)
    end
  end
end
