#ifndef SHOVELERDB_H
#define SHOVELERDB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && defined(SHOVELERDB_BUILD_SHARED)
#define SHOVELERDB_API __declspec(dllexport)
#elif defined(_WIN32) && defined(SHOVELERDB_USE_SHARED)
#define SHOVELERDB_API __declspec(dllimport)
#else
#define SHOVELERDB_API
#endif

#define SHOVELERDB_ABI_VERSION_MAJOR 0
#define SHOVELERDB_ABI_VERSION_MINOR 1
#define SHOVELERDB_ABI_VERSION_PATCH 0

typedef struct shovelerdb_database shovelerdb_database;
typedef struct shovelerdb_result shovelerdb_result;
typedef struct shovelerdb_row shovelerdb_row;

typedef enum shovelerdb_status {
    SHOVELERDB_STATUS_OK = 0,
    SHOVELERDB_STATUS_INVALID_ARGUMENT = 1,
    SHOVELERDB_STATUS_INVALID_HANDLE = 2,
    SHOVELERDB_STATUS_ALLOCATION_FAILED = 3,
    SHOVELERDB_STATUS_PARSE_ERROR = 4,
    SHOVELERDB_STATUS_OBJECT_ERROR = 5,
    SHOVELERDB_STATUS_TRANSACTION_ERROR = 6,
    SHOVELERDB_STATUS_TYPE_ERROR = 7,
    SHOVELERDB_STATUS_VECTOR_ERROR = 8,
    SHOVELERDB_STATUS_PERSISTENCE_ERROR = 9,
    SHOVELERDB_STATUS_IO_ERROR = 10,
    SHOVELERDB_STATUS_UNSUPPORTED = 11,
    SHOVELERDB_STATUS_INTERNAL_ERROR = 12
} shovelerdb_status;

typedef enum shovelerdb_diagnostic_code {
    SHOVELERDB_DIAGNOSTIC_NONE = 0,
    SHOVELERDB_DIAGNOSTIC_INVALID_ARGUMENT = 1,
    SHOVELERDB_DIAGNOSTIC_INVALID_HANDLE = 2,
    SHOVELERDB_DIAGNOSTIC_ALLOCATION = 3,
    SHOVELERDB_DIAGNOSTIC_PARSER = 4,
    SHOVELERDB_DIAGNOSTIC_OBJECT = 5,
    SHOVELERDB_DIAGNOSTIC_TRANSACTION = 6,
    SHOVELERDB_DIAGNOSTIC_TYPE = 7,
    SHOVELERDB_DIAGNOSTIC_VECTOR = 8,
    SHOVELERDB_DIAGNOSTIC_PERSISTENCE = 9,
    SHOVELERDB_DIAGNOSTIC_IO = 10,
    SHOVELERDB_DIAGNOSTIC_UNSUPPORTED = 11,
    SHOVELERDB_DIAGNOSTIC_INTERNAL = 12
} shovelerdb_diagnostic_code;

typedef enum shovelerdb_result_kind {
    SHOVELERDB_RESULT_EMPTY = 0,
    SHOVELERDB_RESULT_MUTATION_COUNT = 1,
    SHOVELERDB_RESULT_ROWS = 2
} shovelerdb_result_kind;

typedef enum shovelerdb_value_kind {
    SHOVELERDB_VALUE_NULL = 0,
    SHOVELERDB_VALUE_INTEGER = 1,
    SHOVELERDB_VALUE_FLOAT = 2,
    SHOVELERDB_VALUE_BOOLEAN = 3,
    SHOVELERDB_VALUE_TEXT = 4,
    SHOVELERDB_VALUE_BLOB = 5,
    SHOVELERDB_VALUE_VECTOR_F32 = 6
} shovelerdb_value_kind;

typedef struct shovelerdb_string_view {
    const char *data;
    size_t len;
} shovelerdb_string_view;

typedef struct shovelerdb_bytes_view {
    const uint8_t *data;
    size_t len;
} shovelerdb_bytes_view;

typedef struct shovelerdb_f32_vector_view {
    const float *data;
    size_t len;
} shovelerdb_f32_vector_view;

SHOVELERDB_API uint32_t shovelerdb_abi_version_major(void);
SHOVELERDB_API uint32_t shovelerdb_abi_version_minor(void);
SHOVELERDB_API uint32_t shovelerdb_abi_version_patch(void);

SHOVELERDB_API shovelerdb_status shovelerdb_open_or_create(
    const char *path,
    shovelerdb_database **out_database
);
SHOVELERDB_API void shovelerdb_close(shovelerdb_database *database);
SHOVELERDB_API shovelerdb_status shovelerdb_checkpoint(
    shovelerdb_database *database
);

SHOVELERDB_API shovelerdb_status shovelerdb_execute(
    shovelerdb_database *database,
    const char *sql,
    shovelerdb_result **out_result
);
SHOVELERDB_API void shovelerdb_result_release(shovelerdb_result *result);

SHOVELERDB_API shovelerdb_result_kind shovelerdb_result_kind_of(
    const shovelerdb_result *result
);
SHOVELERDB_API uint64_t shovelerdb_result_mutation_count(
    const shovelerdb_result *result
);
SHOVELERDB_API size_t shovelerdb_result_column_count(
    const shovelerdb_result *result
);
SHOVELERDB_API shovelerdb_status shovelerdb_result_column_name(
    const shovelerdb_result *result,
    size_t column_index,
    shovelerdb_string_view *out_name
);
SHOVELERDB_API shovelerdb_status shovelerdb_result_next(
    shovelerdb_result *result,
    const shovelerdb_row **out_row
);

SHOVELERDB_API shovelerdb_status shovelerdb_row_value_kind(
    const shovelerdb_row *row,
    size_t column_index,
    shovelerdb_value_kind *out_kind
);
SHOVELERDB_API shovelerdb_status shovelerdb_row_value_int64(
    const shovelerdb_row *row,
    size_t column_index,
    int64_t *out_value
);
SHOVELERDB_API shovelerdb_status shovelerdb_row_value_float64(
    const shovelerdb_row *row,
    size_t column_index,
    double *out_value
);
SHOVELERDB_API shovelerdb_status shovelerdb_row_value_bool(
    const shovelerdb_row *row,
    size_t column_index,
    uint8_t *out_value
);
SHOVELERDB_API shovelerdb_status shovelerdb_row_value_text(
    const shovelerdb_row *row,
    size_t column_index,
    shovelerdb_string_view *out_value
);
SHOVELERDB_API shovelerdb_status shovelerdb_row_value_blob(
    const shovelerdb_row *row,
    size_t column_index,
    shovelerdb_bytes_view *out_value
);
SHOVELERDB_API shovelerdb_status shovelerdb_row_value_vector_f32(
    const shovelerdb_row *row,
    size_t column_index,
    shovelerdb_f32_vector_view *out_value
);

SHOVELERDB_API shovelerdb_diagnostic_code shovelerdb_status_diagnostic_code(
    shovelerdb_status status
);
SHOVELERDB_API const char *shovelerdb_status_message(
    shovelerdb_status status
);
SHOVELERDB_API shovelerdb_status shovelerdb_database_last_diagnostic(
    const shovelerdb_database *database,
    shovelerdb_diagnostic_code *out_code,
    shovelerdb_string_view *out_message
);

#ifdef __cplusplus
}
#endif

#endif
