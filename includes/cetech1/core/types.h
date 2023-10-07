#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#if defined(_MSC_VER)
//  Microsoft
#define CT_MODULE_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
//  GCC
#define CT_MODULE_EXPORT __attribute__((visibility("default")))
#else
//  do nothing and hope for the best?
#define CT_MODULE_EXPORT
#pragma warning Unknown dynamic link import / export semantics.
#endif

#define CT_ATTR_FORMAT(fmt, args) __attribute__((format(printf, fmt, args)))
#define CT_ARRAY_LEN(_name) (sizeof(_name) / sizeof(_name[0]))

#define CT_STRINGIZE(_x) CT_STRINGIZE_(_x)
#define CT_STRINGIZE_(_x) #_x

#define CT_CONCATENATE(_x, _y) CT_CONCATENATE_(_x, _y)
#define CT_CONCATENATE_(_x, _y) _x##_y

typedef struct ct_allocator_t
{
} ct_allocator_t;

typedef struct ct_strid32_t
{
    uint32_t id;
} ct_strid32_t;

typedef struct ct_strid64_t
{
    uint64_t id;
} ct_strid64_t;

#define CT_STRID32_ZERO \
    ((ct_strid32_t){.id = 0})

#define CT_STRID64_ZERO \
    ((ct_strid64_t){.id = 0})
