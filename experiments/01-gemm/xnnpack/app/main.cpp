#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <vector>

#include <xnnpack.h>

namespace {

constexpr size_t M = 128;
constexpr size_t K = 128;
constexpr size_t N = 128;

constexpr uint32_t INPUT_EXTERNAL_ID = 0;
constexpr uint32_t OUTPUT_EXTERNAL_ID = 1;

void check_xnn(xnn_status status, const char* what)
{
    if (status != xnn_status_success) {
        std::cerr
            << "[gemm-xnnpack] ERROR: "
            << what
            << " failed with status "
            << static_cast<int>(status)
            << '\n';

        std::exit(EXIT_FAILURE);
    }
}

void reference_gemm(
    const float* input,
    const float* weights,
    float* output)
{
    // XNNPACK fully-connected layout:
    //
    // input   : [M, K]
    // weights : [N, K]
    // output  : [M, N]
    //
    // output[m, n] =
    //     sum_k input[m, k] * weights[n, k]

    for (size_t m = 0; m < M; ++m) {
        for (size_t n = 0; n < N; ++n) {
            float sum = 0.0f;

            for (size_t k = 0; k < K; ++k) {
                sum +=
                    input[m * K + k] *
                    weights[n * K + k];
            }

            output[m * N + n] = sum;
        }
    }
}

} // namespace

int main()
{
    std::cout << "[gemm-xnnpack] FP32 Fully Connected / GEMM\n";
    std::cout << "[gemm-xnnpack] M=" << M
              << " K=" << K
              << " N=" << N
              << '\n';

    check_xnn(
        xnn_initialize(nullptr),
        "xnn_initialize");

    //
    // XNNPACK may read XNN_EXTRA_BYTES beyond input array boundaries.
    // Allocate padding for buffers passed to XNNPACK.
    //
    constexpr size_t extra_floats =
        (XNN_EXTRA_BYTES + sizeof(float) - 1) / sizeof(float);

    std::vector<float> input(
        M * K + extra_floats);

    std::vector<float> weights(
        N * K + extra_floats);

    std::vector<float> output(
        M * N + extra_floats);

    std::vector<float> reference(
        M * N);

    //
    // Deterministic data.
    //
    for (size_t i = 0; i < M * K; ++i) {
        input[i] =
            static_cast<float>(
                static_cast<int>(i % 17) - 8) /
            8.0f;
    }

    for (size_t i = 0; i < N * K; ++i) {
        weights[i] =
            static_cast<float>(
                static_cast<int>(i % 13) - 6) /
            6.0f;
    }

    std::fill(
        output.begin(),
        output.end(),
        std::numeric_limits<float>::quiet_NaN());

    reference_gemm(
        input.data(),
        weights.data(),
        reference.data());

    //
    // Create a graph with two externally visible tensors:
    //
    // external ID 0 -> input
    // external ID 1 -> output
    //
    // weights are static and internal to the graph.
    //
    xnn_subgraph_t subgraph = nullptr;

    check_xnn(
        xnn_create_subgraph(
            /*external_value_ids=*/2,
            /*flags=*/0,
            &subgraph),
        "xnn_create_subgraph");

    //
    // Input: [M, K]
    //
    const size_t input_dims[] = {
        M,
        K,
    };

    uint32_t input_id = XNN_INVALID_VALUE_ID;

    check_xnn(
        xnn_define_tensor_value(
            subgraph,
            xnn_datatype_fp32,
            /*num_dims=*/2,
            input_dims,
            /*data=*/nullptr,
            INPUT_EXTERNAL_ID,
            XNN_VALUE_FLAG_EXTERNAL_INPUT,
            &input_id),
        "xnn_define_tensor_value(input)");

    //
    // Static weights: [N, K]
    //
    // XNNPACK's fully connected operator expects this layout when
    // XNN_FLAG_TRANSPOSE_WEIGHTS is NOT specified.
    //
    const size_t weight_dims[] = {
        N,
        K,
    };

    uint32_t weight_id = XNN_INVALID_VALUE_ID;

    check_xnn(
        xnn_define_tensor_value(
            subgraph,
            xnn_datatype_fp32,
            /*num_dims=*/2,
            weight_dims,
            weights.data(),
            XNN_INVALID_VALUE_ID,
            /*flags=*/0,
            &weight_id),
        "xnn_define_tensor_value(weights)");

    //
    // Output: [M, N]
    //
    const size_t output_dims[] = {
        M,
        N,
    };

    uint32_t output_id = XNN_INVALID_VALUE_ID;

    check_xnn(
        xnn_define_tensor_value(
            subgraph,
            xnn_datatype_fp32,
            /*num_dims=*/2,
            output_dims,
            /*data=*/nullptr,
            OUTPUT_EXTERNAL_ID,
            XNN_VALUE_FLAG_EXTERNAL_OUTPUT,
            &output_id),
        "xnn_define_tensor_value(output)");

    //
    // Fully connected:
    //
    // Y = X * W^T
    //
    // no bias
    // no activation clipping
    //
    check_xnn(
        xnn_define_fully_connected(
            subgraph,
            -std::numeric_limits<float>::infinity(),
            +std::numeric_limits<float>::infinity(),
            input_id,
            weight_id,
            XNN_INVALID_VALUE_ID,
            output_id,
            /*flags=*/0),
        "xnn_define_fully_connected");

    //
    // Create runtime.
    //
    // The simplest API is sufficient for this first experiment.
    // No explicit thread pool => execution on caller thread.
    //
    xnn_runtime_t runtime = nullptr;

    check_xnn(
        xnn_create_runtime(
            subgraph,
            &runtime),
        "xnn_create_runtime");

    //
    // The runtime no longer depends on the subgraph after creation.
    //
    check_xnn(
        xnn_delete_subgraph(subgraph),
        "xnn_delete_subgraph");

    subgraph = nullptr;

    //
    // Current API separates shape propagation/allocation from
    // binding external buffers.
    //
    check_xnn(
        xnn_reshape_runtime(runtime),
        "xnn_reshape_runtime");

    const xnn_external_value external_values[] = {
        {
            INPUT_EXTERNAL_ID,
            input.data(),
        },
        {
            OUTPUT_EXTERNAL_ID,
            output.data(),
        },
    };

    check_xnn(
        xnn_setup_runtime_v2(
            runtime,
            /*num_external_values=*/2,
            external_values),
        "xnn_setup_runtime_v2");

    check_xnn(
        xnn_invoke_runtime(runtime),
        "xnn_invoke_runtime");

    //
    // Verify against scalar reference.
    //
    float max_abs_error = 0.0f;
    float max_rel_error = 0.0f;

    size_t worst_index = 0;

    for (size_t i = 0; i < M * N; ++i) {
        const float expected = reference[i];
        const float actual = output[i];

        const float abs_error =
            std::abs(actual - expected);

        const float denominator =
            std::max(
                std::abs(expected),
                1.0e-6f);

        const float rel_error =
            abs_error / denominator;

        if (abs_error > max_abs_error) {
            max_abs_error = abs_error;
            worst_index = i;
        }

        max_rel_error =
            std::max(max_rel_error, rel_error);
    }

    std::cout
        << "[gemm-xnnpack] max absolute error: "
        << max_abs_error
        << '\n';

    std::cout
        << "[gemm-xnnpack] max relative error: "
        << max_rel_error
        << '\n';

    std::cout
        << "[gemm-xnnpack] worst element: "
        << worst_index
        << '\n';

    //
    // FP32 reduction order may differ between scalar reference
    // and optimized SIMD microkernels, so do not expect bitwise
    // equality.
    //
    constexpr float tolerance = 1.0e-4f;

    if (max_abs_error > tolerance &&
        max_rel_error > tolerance) {
        std::cerr
            << "[gemm-xnnpack] FAILED\n";

        xnn_delete_runtime(runtime);
        xnn_deinitialize();

        return EXIT_FAILURE;
    }

    std::cout
        << "[gemm-xnnpack] PASSED\n";

    check_xnn(
        xnn_delete_runtime(runtime),
        "xnn_delete_runtime");

    check_xnn(
        xnn_deinitialize(),
        "xnn_deinitialize");

    return EXIT_SUCCESS;
}
