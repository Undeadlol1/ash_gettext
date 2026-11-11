if Code.ensure_loaded?(AshJsonApi.Error) do
  defmodule AshGettext.JsonApi do
    @moduledoc """
    Translates the `detail` of every error in a JSON:API reply. Installed on the
    domain's `error_handler` for you; you never call it.

    Notes for maintainers: maintainers/why-some-errors-are-hard.md in the repository.
    """

    @actor {__MODULE__, :request_actor}
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
      do: Process.put(@actor, Ash.PlugHelpers.get_actor(conn))

    def handle_request(_request_ended, _measurements, _metadata, _config),
      do: Process.delete(@actor)

    @doc "The actor of the request this process is serving, or `nil`."
    @spec request_actor() :: term()
    def request_actor, do: Process.get(@actor)

    @doc """
    Translate `error`'s `detail` into the language of the request's actor.

    The rules are `AshGettext.TransportText`'s: the `detail` is looked up as
    a msgid, with `meta` as its values, then the written sentence for the
    error's `code`. With neither, the error comes back unchanged.
    """
    @spec translate_error(term(), map()) :: term()
    def translate_error(%AshJsonApi.Error{} = error, %{domain: domain}) do
      %{
        error
        | detail:
            AshGettext.TransportText.translate(error.detail, domain,
              code: error.code,
              bindings: error.meta,
              actor: request_actor()
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
