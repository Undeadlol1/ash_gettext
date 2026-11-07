import Config

# Not shipped in the package (see the `files` list in mix.exs). Ash requires
# an explicit answer here, and the fixtures in test/support declare plain
# :string attributes that trip the check.
config :ash, default_string_length_count: :codepoints

# The Ets data layer logs every table it creates at debug level.
config :logger, level: :warning
