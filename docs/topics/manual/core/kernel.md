# Kernel

`Kernel` is main part and entry point for CETech1. Public api is defined `src/core/kernel.zig`
`Kernel` purpose is load and init all modules and run main loop that is make by separate [Phases](#update-phases).

## Kernel task

## Update phases

Kernel main loop call this phases for every tick.
Phases is executed in this serial order one by one.

## .ct_temp/kernel_task_graph.d2

This file contain kernel task graph.

ex. fixtures/test_asset/.ct_temp/kernel_task_graph.d2:

```d2
vars: {d2-config: {layout-engine: elk}}

OnLoad: {
}
OnLoad->PostLoad
PostLoad: {
}
PostLoad->PreUpdate
PreUpdate: {
}
PreUpdate->OnUpdate
OnUpdate: {
    BarUpdate
    FooUpdate
    FooUpdate->FooUpdate2
    FooUpdate2->FooUpdate4
    FooUpdate->FooUpdate4
    FooUpdate2->FooUpdate3
}
OnUpdate->OnValidate
OnValidate: {
}
OnValidate->PostUpdate
PostUpdate: {
}
PostUpdate->PreStore
PreStore: {
}
PreStore->OnStore
OnStore: {
    FooUpdate8
    FooUpdate7
    FooUpdate6
    FooUpdate5
}

```
