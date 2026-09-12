defmodule Mix.Tasks.AshGettext.Extract do
  @shortdoc "Extract Ash `message:` strings into a .pot file"

  @moduledoc """
  Write every translatable Ash `message:` string to a `.pot` file.

      mix ash_gettext.extract
      mix ash_gettext.extract lib apps/other/lib --output priv/gettext/ash_errors.pot
      mix ash_gettext.extract --check

  `mix gettext.extract` only sees calls to gettext macros. Ash error messages are
  `message:` options inside resource DSL and validation modules, so they are
  invisible to it and go out untranslated. This reads the source directly — no
  call site has to be wrapped in `dgettext_noop` for the string to be found.

  ## Options

    * `--output` — where to write the template.
      Defaults to `priv/gettext/ash_errors.pot`.
    * `--check` — write nothing; exit non-zero if the file on disk is not what
      this run would produce. For CI, so a new `message:` cannot land without
      its template entry.

  Interpolated messages (`message: "Bad value: \#{inspect(x)}"`) cannot be msgids
  and are reported at the end rather than skipped silently — each one is a string
  a user may read in a language they did not choose.
  """

  use Mix.Task

  alias AshGettext.Extractor

  @default_output "priv/gettext/ash_errors.pot"
  @default_paths ["lib"]

  @impl Mix.Task
  def run(argv) do
    {opts, paths} = OptionParser.parse!(argv, strict: [output: :string, check: :boolean])

    output = Keyword.get(opts, :output, @default_output)
    paths = if paths == [], do: @default_paths, else: paths

    result = paths |> sources() |> Extractor.scan()
    pot = Extractor.to_pot(result.messages)

    report(result, paths)

    if Keyword.get(opts, :check, false) do
      check(output, pot)
    else
      write(output, pot, length(result.messages))
    end
  end

  defp sources(paths) do
    paths
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{&1, File.read!(&1)})
  end

  defp report(result, paths) do
    Mix.shell().info(
      "Scanned #{Enum.join(paths, ", ")}: #{length(result.messages)} translatable messages."
    )

    case result.interpolated do
      [] ->
        :ok

      interpolated ->
        Mix.shell().info("""

        #{length(interpolated)} interpolated messages cannot be msgids as written:

          #{Enum.map_join(interpolated, "\n  ", &"#{&1.path}:#{&1.line}")}

        Give each one a constant msgid and pass the varying part as a gettext
        binding, e.g. message: "must be at most %{max}" with vars: [max: max].
        """)
    end
  end

  defp write(output, pot, count) do
    output |> Path.dirname() |> File.mkdir_p!()
    File.write!(output, pot)
    Mix.shell().info("Wrote #{count} messages to #{output}.")
  end

  defp check(output, pot) do
    case File.read(output) do
      {:ok, ^pot} ->
        Mix.shell().info("#{output} is up to date.")

      {:ok, _stale} ->
        Mix.raise("""
        #{output} is out of date.

        An Ash `message:` was added, changed or removed without regenerating the
        template, so it has no entry for translators to fill in. Run:

            mix ash_gettext.extract
        """)

      {:error, :enoent} ->
        Mix.raise("#{output} does not exist. Run `mix ash_gettext.extract` to create it.")
    end
  end
end
