defmodule Mix.Tasks.AshGettext.Extract do
  @shortdoc "Extract Ash `message:` strings into a .pot file"

  @moduledoc """
  Write every translatable Ash `message:` string to a `.pot` file.

      mix ash_gettext.extract
      mix ash_gettext.extract lib apps/other/lib --output priv/gettext/shipping.pot
      mix ash_gettext.extract --check

  `mix gettext.extract` only sees calls to gettext macros. Ash error messages are
  `message:` options inside resource DSL and validation modules, so they are
  invisible to it and go out untranslated. This reads the source directly — no
  call site has to be wrapped in `dgettext_noop` for the string to be found.

  ## Options

    * `--output` — where to write the template. Defaults to the file your own
      errors are looked up in: the `priv` directory of the backend your domains
      name, holding `<text_domain>.pot`. A domain with the default
      `text_domain` of `ash` and a backend on the default `priv` gives
      `priv/gettext/ash.pot`. When the app's domains translate into more
      than one template, there is no single answer and this option becomes
      required.
    * `--check` — write nothing; exit non-zero if the file on disk is not what
      this run would produce. For CI, so a new `message:` cannot land without
      its template entry.

  The template also lists, for every resource of a translating domain, the
  attribute labels you wrote in its `gettext` block and the labels and
  descriptions you wrote on its enum values, with a `#.` comment naming the
  attribute they come from. Nothing is made from a code name.

  Interpolated messages (`message: "Bad value: \#{inspect(x)}"`) cannot be msgids
  and are reported at the end rather than skipped silently — each one is a string
  a user may read in a language they did not choose.
  """

  use Mix.Task

  alias AshGettext.Extractor

  @fallback_output "priv/gettext/ash.pot"
  @default_paths ["lib"]

  @impl Mix.Task
  def run(argv) do
    {opts, paths} = OptionParser.parse!(argv, strict: [output: :string, check: :boolean])

    output = Keyword.get_lazy(opts, :output, &default_output/0)
    paths = if paths == [], do: @default_paths, else: paths

    result = paths |> sources() |> Extractor.find_messages()
    messages = Extractor.merge([result.messages, Extractor.resource_messages(resources())])
    pot = Extractor.to_template(messages)

    report(result, messages, paths)

    if Keyword.get(opts, :check, false) do
      check(output, pot)
    else
      write(output, pot, length(messages))
    end
  end

  # Where the template goes when nobody says. It has to be the file the lookups
  # read, which is the backend's priv directory holding `<text_domain>.pot`. A
  # fixed `ash.pot` left anyone who set a custom `text_domain` with a
  # template their own errors never consult.
  defp default_output do
    case configured_templates() do
      [] ->
        @fallback_output

      [only] ->
        only

      several ->
        Mix.raise("""
        The domains in this app translate into more than one template:

          #{Enum.join(several, "\n  ")}

        One run writes one template, so name the one you mean along with the
        sources whose messages belong in it:

            mix ash_gettext.extract lib/my_app/shipping --output #{hd(several)}
        """)
    end
  end

  defp configured_templates do
    domains() |> Enum.flat_map(&template_for/1) |> Enum.uniq()
  end

  defp domains do
    Mix.Task.run("app.config")

    case Keyword.get(Mix.Project.config(), :app) do
      nil -> []
      app -> List.wrap(Application.get_env(app, :ash_domains))
    end
  end

  # Written attribute labels and enum texts of every resource in a translating domain.
  defp resources do
    for domain <- domains(),
        {:ok, _settings} <- [AshGettext.Info.settings(domain)],
        resource <- Ash.Domain.Info.resources(domain),
        do: resource
  end

  defp template_for(domain) do
    with {:ok, %{backend: backend, text_domain: text_domain}} <- AshGettext.Info.settings(domain),
         true <- Code.ensure_loaded?(backend),
         true <- function_exported?(backend, :__gettext__, 1) do
      [Path.join(backend.__gettext__(:priv), "#{text_domain}.pot")]
    else
      _not_translating -> []
    end
  end

  defp sources(paths) do
    paths
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.ex")))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{&1, File.read!(&1)})
  end

  defp report(result, messages, paths) do
    Mix.shell().info(
      "Scanned #{Enum.join(paths, ", ")}: #{length(messages)} translatable messages."
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
