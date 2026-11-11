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

    The text is translated into Gettext's current language for the request.
    If your app does not set it already, `AshGettext.Plug` sets it from the
    actor.

    Only `detail` changes. `code`, `title`, `meta`, `source_pointer` and the
    status stay as they were, so a client that reads them keeps working.

    A `detail` your catalog has no entry for is left exactly as it was. So is
    every reply in the source language, a domain with no `gettext` block and
    one with `translate_errors? false`. A new error from a later Ash release
    passes through until you translate it.

    An `error_handler` you wrote keeps running. It is called first, with the
    arguments you gave it, and the error it returns is then translated.
    """

    alias AshGettext.AshMessages
    alias AshGettext.Info

    @doc """
    Translate `error`'s `detail` into Gettext's current language.

    The `detail` is looked up as a msgid, with `meta` as its values. When the
    catalog has no entry for it, the written sentence for the error's `code`
    (`AshGettext.AshMessages`) is looked up instead. With neither, the error
    comes back unchanged.
    """
    @spec translate_error(term(), map()) :: term()
    def translate_error(%AshJsonApi.Error{detail: detail} = error, %{domain: domain})
        when is_binary(detail) and not is_nil(domain) do
      case Info.settings(domain) do
        {:ok, settings} -> %{error | detail: translated_detail(error, settings)}
        :error -> error
      end
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

    defp translated_detail(%{detail: detail} = error, settings) do
      [detail, AshMessages.reply_msgid(error.code)]
      |> Enum.reject(&is_nil/1)
      |> Enum.find_value(detail, &translation(&1, error, settings))
    end

    defp translation(msgid, error, settings) do
      case AshGettext.translate_or_missing(
             settings.backend,
             settings.text_domain,
             msgid,
             bindings(error.meta),
             Gettext.get_locale(settings.backend)
           ) do
        {:ok, translated} -> translated
        {:missing, _untranslated} -> nil
      end
    end

    defp bindings(meta) when is_map(meta),
      do: Enum.filter(meta, fn {key, _value} -> is_atom(key) end)

    defp bindings(_no_meta), do: []
  end
end
