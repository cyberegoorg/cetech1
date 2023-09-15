#include <stdint.h>

struct ct_api_registry_api_t;

typedef void (*ct_module_fce_t)(const struct ct_api_registry_api_t* api, uint8_t load, uint8_t reload);

typedef struct ct_modules_api_t {
} ct_modules_api_t;

