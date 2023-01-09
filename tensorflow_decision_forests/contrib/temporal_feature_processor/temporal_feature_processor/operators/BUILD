package(
    default_visibility = ["//visibility:public"],
    licenses = ["notice"],
)

# Libraries
# =========

py_library(
    name = "operators",
    srcs = ["__init__.py"],
    srcs_version = "PY3",
    deps = [
        ":assign",
        ":base",
        "//temporal_feature_processor/operators/window",
        "//temporal_feature_processor/sequences",
    ],
)

py_library(
    name = "assign",
    srcs = ["assign.py"],
    srcs_version = "PY3",
)

py_library(
    name = "base",
    srcs = ["base.py"],
    srcs_version = "PY3",
)
