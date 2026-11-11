if Code.ensure_loaded?(AshGraphql.Error) do
  defmodule AshGettext.Graphql do
    @moduledoc """
    Translates `message` and `short_message` of every error in a GraphQL reply.
    Installed on the domain's `error_handler` for you; you never call it.

    Notes for maintainers: maintainers/why-some-errors-are-hard.md in the repository.
    """

    @operation {__MODULE__, :operation}
    @event [:absinthe, :execute, :operation]

    @doc false
    def remember_operations do
      :telemetry.attach_many(
        __MODULE__,
        [@event ++ [:start], @event ++ [:stop]],
        &__MODULE__.handle_operation/4,
        nil
      )
    end

    @doc false
    def handle_operation(
          [:absinthe, :execute, :operation, :start],
          _measurements,
          _meta,
          _config
        ),
        do: Process.put(@operation, %{})

    def handle_operation(_operation_ended, _measurements, _metadata, _config),
      do: Process.delete(@operation)

    @doc """
    Translate `error`'s `message` and `short_message` into the actor's language.

    The rules are `AshGettext.TransportText`'s: the text is looked up as a
    msgid, with `vars` as its values, then the written sentence for the
    error's `code`. With neither, the error comes back unchanged.
    """
    @spec translate_error(term(), map()) :: term()
    def translate_error(%{message: message, short_message: short_message} = error, context) do
      code = if message == short_message, do: error[:code]

      translated = fn text ->
        AshGettext.TransportText.translate(text, context[:domain],
          code: code,
          bindings: error[:vars],
          actor: context[:actor],
          remember_in: @operation
        )
      end

      %{error | message: translated.(message), short_message: translated.(short_message)}
    end

    def translate_error(error, _context), do: error

    @doc """
    Run the app's own `error_handler`, then translate the error it returns.
    AshGraphql's default handler runs after the translation.
    """
    @spec translate_error(term(), map(), {module(), atom(), [term()]}) :: term()
    def translate_error(error, context, {AshGraphql.DefaultErrorHandler, function, arguments}) do
      error
      |> translate_error(context)
      |> then(&apply(AshGraphql.DefaultErrorHandler, function, [&1, context | arguments]))
    end

    def translate_error(error, context, {module, function, arguments}) do
      module
      |> apply(function, [error, context | arguments])
      |> translate_error(context)
    end
  end
end
