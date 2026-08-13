cmake_minimum_required(VERSION 3.24)

project(
    cblas_gemm_demo
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

#
# experiments/01-gemm/cblas
#   -> ../../..
#
get_filename_component(
    AI_COMPILER_LAB_ROOT
    "${CMAKE_CURRENT_SOURCE_DIR}/../../.."
    ABSOLUTE
)

set(
    OPENBLAS_INSTALL_DIR
    "${AI_COMPILER_LAB_ROOT}/build/openblas-install"
)

set(
    OPENBLAS_INCLUDE_DIR
    "${OPENBLAS_INSTALL_DIR}/include/openblas"
)

set(
    OPENBLAS_LIBRARY
    "${OPENBLAS_INSTALL_DIR}/lib/libopenblas.a"
)

#
# Fail early if OpenBLAS has not been built yet.
#
if(NOT EXISTS "${OPENBLAS_INCLUDE_DIR}/cblas.h")
    message(
        FATAL_ERROR
        "OpenBLAS CBLAS header not found:\n"
        "  ${OPENBLAS_INCLUDE_DIR}/cblas.h\n"
        "Run scripts/build-openblas.sh first."
    )
endif()

if(NOT EXISTS "${OPENBLAS_LIBRARY}")
    message(
        FATAL_ERROR
        "OpenBLAS static library not found:\n"
        "  ${OPENBLAS_LIBRARY}\n"
        "Run scripts/build-openblas.sh first."
    )
endif()

add_executable(
    cblas-gemm
    app/main.cpp
)

target_include_directories(
    cblas-gemm
    PRIVATE
        "${OPENBLAS_INCLUDE_DIR}"
)

target_link_libraries(
    cblas-gemm
    PRIVATE
        "${OPENBLAS_LIBRARY}"
        m
        pthread
)

target_compile_options(
    cblas-gemm
    PRIVATE
        -Wall
        -Wextra
        -Wpedantic
)

message(STATUS "AI compiler lab : ${AI_COMPILER_LAB_ROOT}")
message(STATUS "OpenBLAS install: ${OPENBLAS_INSTALL_DIR}")
message(STATUS "OpenBLAS include: ${OPENBLAS_INCLUDE_DIR}")
message(STATUS "OpenBLAS library: ${OPENBLAS_LIBRARY}")
