# Kernel

`Kernel` is main part and entry point for cetech1. Public api is defined [kernel.zig](../src/cetech1/core/kernel.zig)
`Kernel` purpose is load and init all modules and run main loop that is make by seperate [Phases](#update-phases).

## Kernel task

## Update phases

Kernel main loop call this phases for every tick.
Phases is executed in this serial order one by one.

- `OnLoad`
- `PostLoad`
- `PreUpdate`
- `OnUpdate`
- `OnValidate`
- `PostUpdate`
- `PreStore`
- `OnStore`
