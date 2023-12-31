#pragma once
#include "types.h"

#define CT_APIDB_LANG_C "c"
#define CT_APIDB_LANG_ZIG "zig"

#define ct_to_interface(impl_iter, interface_type) ((*interface_type)impl_iter->interface)
#define ct_apidb_name(x) CT_STRINGIZE(x)
#define ct_apidb_api_arg(x) ct_apidb_name(x), sizeof(x)

typedef struct ct_apidb_impl_iter_t
{
    void *interface;
    struct ct_apidb_impl_iter_t *next;
    struct ct_apidb_impl_iter_t *prev;
} ct_apidb_impl_iter_t;

typedef struct ct_apidb_api_t
{
    void (*set_api)(const char *language, const char *api_name, void *api_ptr, uint32_t api_size);
    void *(*get_api)(const char *language, const char *api_name, uint32_t api_size);
    void (*remove_api)(const char *language, const char *api_name);
    void (*set_or_remove)(const char *language, const char *api_name, void *api_ptr, uint32_t api_size, bool load, bool reload);

    void *(*global_var)(const char *module, const char *var_name, uint32_t size, const void *defaultt);

    void (*impl)(const char *interface_name, void *impl_ptr);
    void (*remove_impl)(const char *interface_name, void *impl_ptr);
    void (*impl_or_remove)(const char *interface_name, void *impl_ptr, bool load);
    const ct_apidb_impl_iter_t *(*get_first_impl)(const char *interface_name);
} ct_apidb_api_t;
