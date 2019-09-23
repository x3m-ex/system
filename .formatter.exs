locals_without_parens = [
  # Router
  service: 2,
  service: 3,

  # MessageHandler
  on_new_aggregate: 1,
  on_new_aggregate: 2,
  on_aggregate: 1,
  on_aggregate: 2,

  # Aggregate
  handle_msg: 2,

  # Ecto
  field: 1,
  field: 2,
  field: 3
]

[
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
