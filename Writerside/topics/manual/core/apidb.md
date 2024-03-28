# ApiDB

Main mechanism to use/export api and interfaces across app.

> **API** vs **Interfaces** in context of ApiDb
>
> - **Api** has only one active implementation per language.
> - **Interface** has zero or many implementation.

## Why

1. Primary solve problem for dynamic loading modules to find correct api without need to be compiled with engine.
2. Second reason is if API/Interface provide C compatible API you can use it
   for [FFI](https://en.wikipedia.org/wiki/Foreign_function_interface).
   This mean you can write module in any language that can import/export C ABI compatible binary and use it with engine.
3. To support module hot-reload we need some mechanism to define variable that can survive hot-reload of module. (
   internally we use heap allocated variable)

## API

## Interface
