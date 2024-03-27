# Kernel

`Kernel` is main part and entry point for CETech1. Public api is defined `src/core/kernel.zig`
`Kernel` purpose is load and init all modules and run main loop that is make by separate [Phases](#update-phases).

## Kernel task

## Update phases

Kernel main loop call this phases for every tick.
Phases is executed in this serial order one by one.

```d2
OnLoad
OnLoad->PostLoad
PostLoad->PreUpdate
PreUpdate->OnUpdate
OnUpdate->OnValidate
OnValidate->PostUpdate
PostUpdate->PreStore
PreStore->OnStore
```
