defmodule AshGettext.Test do
  @moduledoc """
  One-line assertions about translated text, for the library's own suite and for
  consumers writing their own.

  > #### Not for host application tests {: .warning}
  >
  > A host's tests should assert the *text its users read*, through the host's
  > own API, so they keep passing whether `ash_gettext` sits behind that API or
  > not. Reaching for these helpers in host tests couples the suite to this
  > library and throws that property away. A host can enforce this with its
  > own static-analysis rule against reaching for `AshGettext.Test` outside
  > this library's own suite.

  These helpers exist for the cases where the library *is* the subject: the
  library's own tests, and a consumer auditing catalog coverage.
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
    case AshGettext.fetch(backend, text_domain, msgid, bindings, locale) do
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
