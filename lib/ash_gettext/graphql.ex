if Code.ensure_loaded?(AshGraphql.Error) do
  defmodule AshGettext.Graphql do
    @moduledoc """
    Translate the errors a GraphQL reply carries.

    AshGraphql writes the text of some errors itself: "is required" for a
    missing value, "could not be found" for a record that is not there. It does
    so when it turns the Ash error into a GraphQL one, after every Ash error
    handler has run, and for reads too, so the reply is the one place every
    error passes with its final text.

    There is nothing to set up. A domain with a `gettext` block that also uses
    `AshGraphql.Domain` gets this as its `error_handler`
    (`AshGettext.Domain.Transformers.TranslateReplies`).

    AshGraphql hands the handler the request's context, and the actor is in it.
    The language is the one the domain's `locale_resolver` answers for that
    actor, so no plug or `Gettext.put_locale/2` is needed. Without an actor,
    Gettext's current language is used.

    Only `message` and `short_message` change. `code`, `fields`, `path` and
    everything else stay as they were, so a client that reads them keeps
    working.

    A text your catalog has no entry for is left exactly as it was. So is every
    reply in the source language, a domain with no `gettext` block and one with
    `translate_errors? false`. A new error from a later Ash release passes
    through until you translate it.

    GraphQL checks the document against the schema before Ash sees it. Those
    errors ("Argument ... has invalid value ...") come from Absinthe and are not
    translated here.

    An `error_handler` you wrote keeps running. It is called first, with the
    arguments you gave it, and the error it returns is then translated.
    """

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
          actor: context[:actor]
        )
      end

      %{error | message: translated.(message), short_message: translated.(short_message)}
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
