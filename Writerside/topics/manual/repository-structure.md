# Repository structure

| Folder                                                                                                | Description                                                         |
|-------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| [`Writerside/`](https://github.com/cyberegoorg/cetech1/tree/main/Writerside/)                         | This documentation                                                  |
| [`zig/`](https://github.com/cyberegoorg/cetech1/tree/main/zig/)                                       | Submodule for prebuilt zig                                          |
| [`externals/`](https://github.com/cyberegoorg/cetech1/tree/main/externals/)                           | 3rd-party library and tools                                         |
| [`fixtures/`](https://github.com/cyberegoorg/cetech1/tree/main/fixtures/)                             | Tests fixtures                                                      |
| [`src/includes/`](https://github.com/cyberegoorg/cetech1/tree/main/src/includes/)                     | C api headers                                                       |
| [`src/`](https://github.com/cyberegoorg/cetech1/tree/main/src)                        | Main source code folder                                             |
| [`src/private`](https://github.com/cyberegoorg/cetech1/tree/main/src/private)         | Private api. Use only if you extend core                            |
| [`modules/`](https://github.com/cyberegoorg/cetech1/tree/main/modules/)                               | There is all modules that is possible part of engine                |
| [`examples/foo`](https://github.com/cyberegoorg/cetech1/tree/main/examples/foo)                       | Simple `foo` module write in zig                                    |
| [`examples/bar`](https://github.com/cyberegoorg/cetech1/tree/main/examples/bar)                       | Simple `bar` module write in C and use api exported by `foo` module |
| [`examples/editor_foo_tab`](https://github.com/cyberegoorg/cetech1/tree/main/examples/editor_foo_tab) | Show how to crete new editor tab type                               |
