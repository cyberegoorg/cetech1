# AssetDB

AssetDb is persistent layer for [CDB](cdb.md) that support import/export of asset from fs, net etc...


> **Asset** vs **Asset object**
>
> - **Asset** is only wrapper that hold asset object as subobject, name and folder.
> - **Asset object** is real asset that you can use. but in some context can be call Asset.

> **Directory** vs **Folder**
>
> - **Directory** is real dir on FS
> - **Folder** is CDB object that act as abstraction for FS structure and can hold metadata like tags, description,
    color etc...

## Why

1. Because [CDB](cdb.md) is strictly memory-oriented we need some mechanism to load/save it.
2. We need mechanism for convert DCC assets like Texture/Meshes/Scene to CDB object that can be used inside engine.
3. We need support VCS systems like Git.

## How it works

- AssetDB map UUID to cdbobj if obj go thru it via save/load methods.
- Asset is [CDB](cdb.md) object associated with name, folder and is load/save from fs, net etc.
- Asset act like wrapper for real asset object that is store inside "asset" property.

## Asset JSON base format

Assets are saved as valid JSON object. Filename is derived form asset name, CDB type and path by folder
ex.: `core/core_subfolder/foo_subcore.ct_foo_asset` has asset name `foo_subcore`,CDB type `ct_foo_asset` and is in
folder `core_subfolder`.

```JSON
{
  "__version": "0.1.0",
  "__asset_uuid": "018b5c74-06f7-740e-be81-d727adec5fb4",
  "__description": "Simple test asset",
  "__type_name": "ct_foo_asset",
  "__uuid": "018b5c74-06f7-79fd-a6ad-3678552795a1",
  "__prototype_uuid": "018b5846-c2d5-712f-bb12-9d9d15321ecb",
  "u64": 110,
  "i64": 220,
  "str": "foo subcore",
  "blob": "e1ae88d73f1f6a11",
  "subobject": {
    "__type_name": "ct_foo_asset",
    "__uuid": "018b5c74-06f7-7472-b90c-945f1737ba9d"
  },
  "subobject_set": [
    {
      "__type_name": "ct_foo_asset",
      "__uuid": "018b5c74-06f7-70bb-94e3-10a2a8619d31"
    }
  ],
  "subobject_set__instantiate": [
    {
      "__type_name": "ct_foo_asset",
      "__uuid": "7d0d10ce-128e-45ab-8c14-c5d486542d4f",
      "__prototype_uuid": "018b5846-c2d5-7584-9183-a95f78095230"
    }
  ],
  "subobject_set__removed": [
    "ct_foo_asset:9986f5cc-bc90-4443-8ad0-83357c02d28d"
  ],
  "reference_set__removed": [
    "ct_foo_asset:028ef368-9b36-44f9-b8cc-d377365f836c"
  ]
}
```

Reserved keyword begin with`__` prefix and some with `__` postfix after property name.
Reference UUID is in format `cdb_type_name:UUID`.

| Keyword                   | Required                          | Description                                                                                                           |
|---------------------------| --------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `__version`               | Yes                               | File format version in semver format                                                                                  |
| `__asset_uuid`            | Only for top-level                | UUID for asset wrapper not asset object                                                                               |
| `__description`           | No and allowed only for top-level | Descritption for asset                                                                                                |
| `__type_name`             | Yes                               | CDB type name as string                                                                                               |
| `__uuid`                  | Yes                               | UUID of asset object                                                                                                  |
| `__prototype_uuid`        | No                                | If object is based on prototype must have this filed                                                                  |
| `<PROPNAME>__instantiate` | No                                | This create subobject instance from prototype, and replace it in set. Valid only for `SUBOBJECT_SET` base properties. |
| `<PROPNAME>__removed`     | No                                | This remove subobject from set. Valid only for `_SET` base properties.                                                |
