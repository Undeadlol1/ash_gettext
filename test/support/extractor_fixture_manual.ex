defmodule ExtractorFixture.Manual do
  @moduledoc "A manual create that fails with a message."

  use Ash.Resource.ManualCreate

  @impl true
  def create(_changeset, _opts, _context), do: {:error, message: "the manual action refused"}
end
