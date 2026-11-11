if Code.ensure_loaded?(AshJsonApi.Error) do
  defmodule AshGettext.JsonApi do
    @moduledoc """
    Translate the errors a JSON:API reply carries.

    AshJsonApi writes the text of some errors itself: "is required" for a
    missing value, "No note record found with ..." for a record that is not
    there. It does so after every Ash error handler has run, and for reads too,
    so the reply is the one place every error passes with its final text.

    There is nothing to set up. A domain with a `gettext` block that also uses
    `AshJsonApi.Domain` gets this as its `error_handler`
    (`AshGettext.Domain.Transformers.TranslateJsonApiReplies`).

    The language is the one the domain's `locale_resolver` answers for the
    request's actor. AshJsonApi does not tell an `error_handler` who the actor
    is, so this module listens to the event `Plug.Router` sends when a request
    enters a router and remembers the actor (`Ash.PlugHelpers.get_actor/1`)
    until the request ends. Without an actor, Gettext's current language is
    used.

    Only `detail` changes. `code`, `title`, `meta`, `source_pointer` and the
    status stay as they were, so a client that reads them keeps working.

    A `detail` your catalog has no entry for is left exactly as it was. So is
    every reply in the source language, a domain with no `gettext` block and
    one with `translate_errors? false`. A new error from a later Ash release
    passes through until you translate it.

    An `error_handler` you wrote keeps running. It is called first, with the
    arguments you gave it, and the error it returns is then translated.
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
