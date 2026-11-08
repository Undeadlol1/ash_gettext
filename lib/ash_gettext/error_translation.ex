defmodule AshGettext.ErrorTranslation do
  @moduledoc """
  Turn an Ash error's message into the reader's language.

  Ash errors are Splode structs carrying a `:message` and a bag of `:vars`, and
  every transport renders that same struct — JSON:API puts it in `detail`,
  GraphQL in the error message, gRPC in the status. Translating the struct once
  therefore covers every transport at once, including ones not written yet.

  The `:message` *is* the msgid. A message the catalog covers is replaced; one it
  does not is left exactly as it was, so adopting this can only ever add
  translations, never mangle an existing message.

  Ash's own errors with no message (a missing required value, a failed policy)
  get the written sentence from `AshGettext.AshMessages`, translated, and come
  back as an `AshGettext.AshMessages.Translated` that keeps the original.

  Pure by construction: backend, text domain and locale are all arguments, so a
  test is one assertion over one struct — no action run, no database, no actor.

  `AshGettext.ErrorTranslation.ErrorHandler` calls this each time a create,
  update or destroy action fails on a resource that uses `AshGettext.Resource`.
  You can also call it yourself on any error you already hold.
  """

  @type option ::
          {:backend, module()}
          | {:text_domain, String.t()}
          | {:locale, String.t()}

  @doc """
  Translate `error`'s message, leaving anything untranslatable untouched.

  Handles a bare error struct, a list of them, and a class error whose nested
  `:errors` hold the real messages. An error with no message that
  `AshGettext.AshMessages` lists gets its sentence; anything else without a
  binary `:message` comes back as it was. Missing options raise `KeyError`.

      AshGettext.ErrorTranslation.translate(error,
        backend: MyApp.Gettext,
        text_domain: "ash",
        locale: "ru"
      )

  ## Options

    * `:backend` — required; the Gettext backend to look the msgid up in.
    * `:text_domain` — required; the gettext text domain to look it up under.
    * `:locale` — required; the locale to render in.
  """
  @spec translate(term(), [option()]) :: term()
  def translate(errors, opts) when is_list(errors) do
    Enum.map(errors, &translate(&1, opts))
  end

  def translate(%{errors: nested} = error, opts) when is_list(nested) do
    translate_message(%{error | errors: translate(nested, opts)}, opts)
  end

  def translate(error, opts) when is_struct(error) do
    translate_message(error, opts)
  end

  def translate(error, _opts), do: error

  defp translate_message(%{message: message} = error, opts) when is_binary(message) do
    backend = Keyword.fetch!(opts, :backend)
    text_domain = Keyword.fetch!(opts, :text_domain)
    locale = Keyword.fetch!(opts, :locale)

    case AshGettext.translate_or_missing(backend, text_domain, message, bindings(error), locale) do
      {:ok, translated} -> %{error | message: translated}
      {:missing, _untranslated} -> error
    end
  end

  # Ash's own errors print from code names; give them the written sentence.
  defp translate_message(error, opts) do
    case AshGettext.AshMessages.msgid(error) do
      nil ->
        error

      msgid ->
        AshGettext.AshMessages.Translated.exception(
          original: error,
          field: Map.get(error, :field),
          path: error.path,
          class: error.class,
          message:
            AshGettext.translate(
              Keyword.fetch!(opts, :backend),
              Keyword.fetch!(opts, :text_domain),
              msgid,
              bindings(error),
              Keyword.fetch!(opts, :locale)
            )
        )
    end
  end

  # Splode collects interpolation values in `vars`; they are the bindings a
  # catalog entry like "must be at least %{min} kg" needs.
  defp bindings(error) do
    error
    |> Map.get(:vars, [])
    |> List.wrap()
    |> Enum.filter(&match?({key, _value} when is_atom(key), &1))
  end
end
