# Extracting messages

## Run Gettext's command

```
mix gettext.extract --merge
```

It finds your enum labels, attribute labels, `message:` strings and Ash's
error sentences. Run it again after upgrading Ash or AshGettext: new
sentences land in your template, and you translate them.

`--merge` also updates each language's `.po` file. Translators fill in the
`msgstr` lines, for example in `priv/gettext/ru/LC_MESSAGES/ash.po`:

```po
msgid "This email is already registered"
msgstr "Этот email уже зарегистрирован"
```

Each text goes to the backend and `text_domain` of its domain's `gettext`
block (an enum uses its own `backend:` and `text_domain:`). With the default
text domain that is `priv/gettext/ash.pot`.

## What it finds

- Every `label` and `description` you wrote on an `AshGettext.Enum` value.
- Every `label` in a resource's `gettext` block.
- Every `message` in a resource's DSL: validations, identities and the rest,
  and every policy's `error_message`.
- Every literal `message:` in the validation, change, preparation, generic-action
  `run`, `manual` action and calculation modules a resource uses. Their source files are read.
- Every sentence Ash writes itself: "must be present", "length must be less
  than or equal to %{max}" and the rest (about 60 today), plus "has already
  been taken".
- The sentences for errors that carry no text, and the ones AshJsonApi and
  AshGraphql write, such as "could not be found".

Resources count when they use `AshGettext.Resource` and their domain has a
`gettext` block. A domain without one adds nothing. With
`translate_errors? false`, only the labels are added.

## Fail CI when a template is stale

```
mix gettext.extract --check-up-to-date
```

It writes nothing and fails when a template is out of date, so a new message
cannot be merged without its entry.

## Text outside Ash

Text that is not in a resource, an enum or a module a resource uses, such as a
helper that builds errors, is plain Elixir code. Gettext's usual rules apply:
see [Gettext's docs](https://hexdocs.pm/gettext/Gettext.html).

## Fix a message with a variable in it

A message written with `#{...}` is not a constant, so it cannot be a msgid.
`mix gettext.extract` prints a warning with its file and line. Rewrite it with
a placeholder and pass the value in `vars`:

```elixir
# before
message: "must be at most #{max}"

# after
message: "must be at most %{max}", vars: [max: max]
```
