package(
    default_visibility = ["//visibility:public"],
    licenses = ["notice"],
)

# Libraries
# =========

py_library(
    name = "window",
    srcs = ["__init__.py"],
    srcs_version = "PY3",
    deps = [
        ":base",
        ":simple_moving_average",
        "//temporal_feature_processor/sampling",
    ],
)

py_library(
    name = "base",
    srcs = ["base.py"],
    srcs_version = "PY3",
)

py_library(
    name = "simple_moving_average",
    srcs = ["simple_moving_average.py"],
    srcs_version = "PY3",
)
