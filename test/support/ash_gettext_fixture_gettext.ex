defmodule AshGettextFixture.Gettext do
  @moduledoc """
  A gettext backend owned by this suite, for testing AshGettext.

  The library must work against any host's backend, so it is proven against a
  backend of its own rather than a real application's: catalogs a host happens
  to ship would quietly become part of the library's guarantees. Catalogs live
  in `priv/test_gettext/`.
  """
  use Gettext.Backend, otp_app: :ash_gettext, priv: "priv/test_gettext"
end
