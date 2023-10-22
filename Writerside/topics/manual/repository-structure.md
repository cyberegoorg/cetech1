# Repository structure

| Folder                                                                                                                                        | Description                                                         |
|-----------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| [`bin/zig/`](https://github.com/cyberegoorg/cetech1/tree/main/bin/)                                                                           | Submodule for prebuilt zig                                          |
| [`externals/`](https://github.com/cyberegoorg/cetech1/tree/main/externals/)                                                                   | 3rd-party library and tools                                         |
| [`includes/`](https://github.com/cyberegoorg/cetech1/tree/main/includes/)                                                                     | C api headers                                                       |
| [`tests/`](https://github.com/cyberegoorg/cetech1/tree/main/tests/)                                                                           | Tests fixtures                                                      |
| `tests/tmp/`                                                                                                                                  | Tests use this folder for tmp output/input                          |
| [`Writerside/`](https://github.com/cyberegoorg/cetech1/tree/main/Writerside/)                                                                 | This documentation                                                  |
| [`src/cetech1/`](https://github.com/cyberegoorg/cetech1/tree/main/src/cetech1)                                                                | Main source code folder                                             | 
| [`src/cetech1/core/`](https://github.com/cyberegoorg/cetech1/tree/main/src/cetech1/core/)                                                     | Public api for engie core                                           |
| [`src/cetech1/core/private`](https://github.com/cyberegoorg/cetech1/tree/main/src/cetech1/core/private)                                       | Private api. Use only if you extend core                            |
| [`src/cetech1/modules/`](https://github.com/cyberegoorg/cetech1/tree/main/src/cetech1/modules/)                                               | There is all modules that is possible part of engine                |
| [`src/cetech1/modules/examples/foo`](https://github.com/cyberegoorg/cetech1/tree/main/src/cetech1/modules/examples/foo)                       | Simple `foo` module write in zig                                    |
| [`src/cetech1/modules/examples/bar`](https://github.com/cyberegoorg/cetech1/tree/main/src/cetech1/modules/examples/bar)                       | Simple `bar` module write in C and use api exported by `foo` module |
| [`src/cetech1/modules/examples/editor_foo_tab`](https://github.com/cyberegoorg/cetech1/tree/main/src/cetech1/modules/examples/editor_foo_tab) | Show how to crete new editor tab type                               |
