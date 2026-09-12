defmodule AshGettext.DomainTest do
  @moduledoc """
  Pins the shape of the `gettext do ... end` contract itself.

  These assert on the extension's schema rather than on a configured domain, so
  they fail when an option is quietly renamed, made optional, or given a
  different default — the kind of change that would silently alter behaviour for
  every consumer once this is a published package.
  """

  use ExUnit.Case, async: true

  defp gettext_schema do
    [section] = AshGettext.Domain.sections()
    section.schema
  end

  defp option(name), do: Keyword.fetch!(gettext_schema(), name)

  test "the section is named gettext" do
    assert [%{name: :gettext}] = AshGettext.Domain.sections()
  end

  test "a backend must be declared, since nothing can be derived without one" do
    assert option(:backend)[:required]
  end

  test "the default locale defaults to en" do
    assert option(:default_locale)[:default] == "en"
  end

  test "the text domain defaults to ash_errors, the file mix ash_gettext.extract writes" do
    assert option(:text_domain)[:default] == "ash_errors"
  end

  test "locale resolvers default to reading the action context" do
    assert option(:locale_resolvers)[:default] == [AshGettext.Locale.Context]
  end

  test "locale resolvers must implement the resolver behaviour" do
    assert option(:locale_resolvers)[:type] ==
             {:list, {:behaviour, AshGettext.Locale.Resolver}}
  end

  test "error translation is on once a domain configures gettext" do
    assert option(:translate_errors?)[:default] == true
  end

  test "supported locales are not declarable, so they cannot drift from the catalogs" do
    refute Keyword.has_key?(gettext_schema(), :supported_locales)
    refute Keyword.has_key?(gettext_schema(), :locales)
  end
end
