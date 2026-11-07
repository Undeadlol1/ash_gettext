defmodule AshGettext.Testing do
  @moduledoc """
  One-line assertions about translated text.

  `assert_translates/6` checks the exact text a message renders as.
  `assert_covered/5` checks that a catalog has an entry for it, without pinning
  the wording. Both take the locale as an argument, so tests that use them can
  run `async: true`.

  See the "How to test with AshGettext" guide for examples.
  """

  import ExUnit.Assertions

  @doc """
  Assert that `msgid` renders as `expected` in `locale`.

  Returns the translated string so it can be piped into further assertions.
  """
  @spec assert_translates(
          AshGettext.backend(),
          AshGettext.text_domain(),
          AshGettext.msgid(),
          AshGettext.locale(),
          String.t(),
          AshGettext.bindings()
        ) :: String.t()
  def assert_translates(backend, text_domain, msgid, locale, expected, bindings \\ []) do
    actual = AshGettext.translate(backend, text_domain, msgid, bindings, locale)

    assert actual == expected, """
    Expected #{inspect(msgid)} in #{inspect(locale)} to render as:

      #{inspect(expected)}

    but the #{inspect(text_domain)} catalog produced:

      #{inspect(actual)}
    """

    actual
  end

  @doc """
  Assert that `locale`'s catalog covers `msgid` at all.

  Use this to prove a string is translated without pinning the exact wording —
  useful for coverage sweeps across every supported locale.
  """
  @spec assert_covered(
          AshGettext.backend(),
          AshGettext.text_domain(),
          AshGettext.msgid(),
          AshGettext.locale(),
          AshGettext.bindings()
        ) :: String.t()
  def assert_covered(backend, text_domain, msgid, locale, bindings \\ []) do
    case AshGettext.translate_or_missing(backend, text_domain, msgid, bindings, locale) do
      {:ok, translated} ->
        translated

      {:missing, _fallback} ->
        flunk("""
        #{inspect(msgid)} has no translation in #{inspect(locale)}.

        Expected the #{inspect(text_domain)} catalog for #{inspect(locale)} to
        cover it, but the lookup fell through to the msgid itself.
        """)
    end
  end
end
