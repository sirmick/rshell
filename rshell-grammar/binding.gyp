{
  "targets": [
    {
      "target_name": "tree_sitter_rshell_binding",
      "include_dirs": [
        "<!(node -e \"require('nan')\")",
        "src"
      ],
      "sources": [
        "bindings/node/binding.cc",
        "src/parser.c",
        "src/scanner.cc",
        "src/scanner_c_api.cc"
      ],
      "cflags_c": [
        "-std=c99",
      ],
      "cflags_cc": [
        "-std=c++20",
      ]
    }
  ]
}
