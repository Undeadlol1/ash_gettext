defmodule ExtractorFixture.Run do
  @moduledoc "A generic action's run module that fails with a message."

  use Ash.Resource.Actions.Implementation

  @impl true
  def run(_input, _opts, _context), do: {:error, message: "the run module refused"}
end
