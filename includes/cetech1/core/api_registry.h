#include <stdint.h>

typedef struct ct_api_registry_api_t {
    void (*add_api)(const char* api_name, void* api_ptr);
    void* (*get_api)(const char* api_name);
} ct_api_registry_api_t;
