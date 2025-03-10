# About

[CETech1](https://github.com/cyberegoorg/cetech1) is experimental game engine write in awesome language
named [zig](https://ziglang.org).
Some core features like [AsseDB](assetdb.md), [CDB](cdb.md) and [ApiDB](apidb.md) is based on BitSquid/OurMachinery blog
posts.

## Goals

- Small reusable blocks that you can combine for what your project need. This is opposite to engine like Unreal, Unity
  etc.
- Zero-work editor UI for new asset/data types. You can start with automatic-default and customize it later on your
  needed.
- Fast iteration on ideas by hot-reload assets and code.
- Multiplatform runtime + editor
- Hackable
- And one day real game using this technology ;)

## Plan

### 0.1.0 - Core (current WIP)

- Basic concept for core (Assets, CDB, Window, Input, UI)
- Support for modules with hot-reload
- Supported platforms `macOS`, `linux/steamdeck`, `windows`
- Editor basic concept
- Automatic test for UI
- Unittest
- GPU/GFX
- Render graph
- ECS
- Actions (HL concept for Input)
- Localization for UI/Editor

## Credits/Licenses For Fonts Included In Repository

Some fonts files are available in the `src/embed/fonts/` folder:

- **[Roboto-Medium.ttf](https://fonts.google.com/specimen/Roboto)** - Apache License 2.0
- **[fa-regular-400.ttf](https://fontawesome.com)** - SIL OFL 1.1 License
