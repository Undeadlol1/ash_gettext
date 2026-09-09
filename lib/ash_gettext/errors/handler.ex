defmodule AshGettext.Errors.Handler do
  @moduledoc """
  The `error_handler` that `AshGettext.Resource` installs on write actions.

  Ash calls this with the changeset and each error it collects, and takes the
  return value as the error to keep. Two things happen here and nowhere else:
  the locale is resolved from the changeset, and the error is handed to
  `AshGettext.Errors`.

  It sits below every transport by design (see the notebook §2.0d). It also sits
  below every *validation* — an error raised by a custom validation, a builtin
  constraint, or the data layer all arrive here the same way.

  If the domain does not configure `gettext`, the error passes through untouched.
  """

  alias AshGettext.Errors
  alias AshGettext.Info
  alias AshGettext.Locale

  @doc """
  Translate `error` into the locale `changeset` implies.
  """
  @spec handle(Ash.Changeset.t(), term()) :: term()
  def handle(changeset, error) do
    case Info.settings(changeset.domain) do
      {:ok, settings} -> Errors.translate(error, translation_options(changeset, settings))
      :error -> error
    end
  end

  defp translation_options(changeset, settings) do
    [
      backend: settings.backend,
      text_domain: settings.text_domain,
      locale: locale(changeset, settings)
    ]
  end

  defp locale(changeset, settings) do
    changeset
    |> resolution_context()
    |> Locale.resolve(
      resolvers: settings.locale_resolvers,
      supported: settings.supported_locales,
      default: settings.default_locale
    )
  end

  # The actor lives under `context.private` where Ash puts it; a resolver should
  # not have to know that, so it is lifted alongside an explicitly passed locale.
  defp resolution_context(changeset) do
    context = changeset.context || %{}

    %{
      locale: context[:locale],
      actor: get_in(context, [:private, :actor]),
      changeset: changeset
    }
  end
end
