#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <vector>

#include <cblas.h>

namespace {

constexpr int M = 128;
constexpr int K = 128;
constexpr int N = 128;

void reference_gemm(
    const float* input,
    const float* weights,
    float* output)
{
    // Match the XNNPACK demo layout:
    //
    // input   : [M, K]
    // weights : [N, K]
    // output  : [M, N]
    //
    // output[m, n] =
    //     sum_k input[m, k] * weights[n, k]
    //
    // Mathematically:
    //
    // C = A * W^T

    for (int m = 0; m < M; ++m) {
        for (int n = 0; n < N; ++n) {
            float sum = 0.0f;

            for (int k = 0; k < K; ++k) {
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
    std::cout << "[gemm-cblas] FP32 SGEMM\n";
    std::cout << "[gemm-cblas] M=" << M
              << " K=" << K
              << " N=" << N
              << '\n';

    std::cout << "[gemm-cblas] OpenBLAS config: "
              << openblas_get_config()
              << '\n';

    std::cout << "[gemm-cblas] OpenBLAS core: "
              << openblas_get_corename()
              << '\n';

    std::vector<float> input(M * K);
    std::vector<float> weights(N * K);
    std::vector<float> output(M * N);
    std::vector<float> reference(M * N);

    //
    // Use exactly the same deterministic initialization as the
    // XNNPACK experiment.
    //
    for (int i = 0; i < M * K; ++i) {
        input[i] =
            static_cast<float>((i % 17) - 8) /
            8.0f;
    }

    for (int i = 0; i < N * K; ++i) {
        weights[i] =
            static_cast<float>((i % 13) - 6) /
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
    // input   is [M, K]
    // weights is [N, K]
    //
    // We want:
    //
    //     output = input * weights^T
    //
    // Therefore use CblasTrans for the second matrix.
    //
    cblas_sgemm(
        CblasRowMajor,
        CblasNoTrans,
        CblasTrans,

        M,
        N,
        K,

        1.0f,

        input.data(),
        K,

        weights.data(),
        K,

        0.0f,

        output.data(),
        N);

    float max_abs_error = 0.0f;
    float max_rel_error = 0.0f;

    std::size_t worst_index = 0;

    for (std::size_t i = 0; i < output.size(); ++i) {
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
        << "[gemm-cblas] max absolute error: "
        << max_abs_error
        << '\n';

    std::cout
        << "[gemm-cblas] max relative error: "
        << max_rel_error
        << '\n';

    std::cout
        << "[gemm-cblas] worst element: "
        << worst_index
        << '\n';

    //
    // BLAS kernels may accumulate in a different order than the
    // simple scalar reference, so bitwise equality is not expected.
    //
    constexpr float tolerance = 1.0e-4f;

    if (max_abs_error > tolerance &&
        max_rel_error > tolerance) {
        std::cerr
            << "[gemm-cblas] FAILED\n";

        return EXIT_FAILURE;
    }

    std::cout
        << "[gemm-cblas] PASSED\n";

    return EXIT_SUCCESS;
}
