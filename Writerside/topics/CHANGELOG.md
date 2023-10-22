# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **core:api:zig**: StrId{32, 64}
- **core:api:zig**: ApiDbAPI
- **core:api:zig**: LogAPI
- **core:api:zig**: TaskApi
- **core:api:zig**: BAG (before-after graph)
- **core:api:zig**: Uuid
- **core:api:zig**: CDB
- **core:api:zig**: AssetDB

- **modules:editor_explorer:** Basic CDB object explorer
- **modules:editor_properties_editor:** Basic propperties editor
- **modules:editor_asset_browser:** Basic asset browser tab
- **modules:editor:** Initial Editor with tabs support
- **core:editorui:** Tree widget for cdb
- **core:editorui:** Initial EditorUI support (via zgui => ImGUI)
- **core:assetdb:** Initial AssetDB support
- **core:assetdb:** Generate asset graph MD to .ct_temp folder
- **core:cdb:** Initial CDB support
- **core:profiler:** Profler support (via Tracy)
- **core:task:** Task support (via zjobs)

- **core:kernel**: Boot
- **core:kernel**: Task and Phases
- **core:kernel:** Generate kernel task phase MD graph to .ct_temp folder

- **core:apidb**: Global variable
- **core:apidb**: Set/Get api
- **core:apidb**: Impl/iter interface
- **core:apidb**: Interface generation number for change watching

- **core:modules**: Dynamic modules with hot-reload
- **core:modules**: Static moduels

- **core:log**: Basic scoped logging

- **gitub**: actions with cross-compile
- **test**: init setup
- **repo**: init structures
