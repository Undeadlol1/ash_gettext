defmodule AshGettext.Locale.Resolver do
  @moduledoc """
  Reads a user's language from the actor.

  Name one in the domain's `gettext` block with `locale_resolver`. It is called
  only with a non-nil actor. Return `nil` to use Gettext's current process
  language.

      defmodule MyApp.LocaleResolver do
        @behaviour AshGettext.Locale.Resolver

        @impl true
        def resolve(%{language: language}), do: language
        def resolve(_actor), do: nil
      end
  """

  @doc """
  Return the actor's language, or `nil` for Gettext's current process language.
  """
  @callback resolve(actor :: term()) :: String.t() | nil
end
