# ApiDB

Main mechanism to use/export api and interfaces across app.

> **API** vs **Interfaces** in context of ApiDb
>
> - **Api** has only one active implementation per language.
> - **Interface** has zero or many implementation.

## Why

1. Primary solve problem for dynamic loading modules to find correct api without need to be compiled with engine.
2. To support module hot-reload we need some mechanism to define variable that can survive hot-reload of module. (
   internally we use heap allocated variable)

## API

## Interface

## .ct_temp/apidb_graph.d2

This file contain module/api dependency graph.
