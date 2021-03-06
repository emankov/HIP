#!/bin/bash

#set -x
LLVM_DIR="$1/../../../"
tmp=/tmp/hip_pch.$$
mkdir -p $tmp

cat >$tmp/hip_macros.h <<EOF
#define __device__ __attribute__((device))
#define __host__ __attribute__((host))
#define __global__ __attribute__((global))
#define __constant__ __attribute__((constant))
#define __shared__ __attribute__((shared))

#define launch_bounds_impl0(requiredMaxThreadsPerBlock)                                            \
    __attribute__((amdgpu_flat_work_group_size(1, requiredMaxThreadsPerBlock)))
#define launch_bounds_impl1(requiredMaxThreadsPerBlock, minBlocksPerMultiprocessor)                \
    __attribute__((amdgpu_flat_work_group_size(1, requiredMaxThreadsPerBlock),                     \
                   amdgpu_waves_per_eu(minBlocksPerMultiprocessor)))
#define select_impl_(_1, _2, impl_, ...) impl_
#define __launch_bounds__(...)                                                                     \
    select_impl_(__VA_ARGS__, launch_bounds_impl1, launch_bounds_impl0)(__VA_ARGS__)

// Macro to replace extern __shared__ declarations
// to local variable definitions
#define HIP_DYNAMIC_SHARED(type, var) \
    type* var = (type*)__amdgcn_get_dynamicgroupbaseptr();
EOF

cat >$tmp/hip_pch.h <<EOF
#include "hip/hip_runtime.h"
#include "hip/hip_fp16.h"
EOF


cat >$tmp/hip_pch.mcin <<EOF
 .type __hip_pch,@object
  .section .hip_pch,"aMS",@progbits,1
  .data
  .globl __hip_pch
  .globl __hip_pch_size
  .p2align 3
__hip_pch:
  .incbin "$tmp/hip.pch"
__hip_pch_size:
  .long __hip_pch_size - __hip_pch
EOF

$LLVM_DIR/bin/clang -O3 -c -std=c++17 -isystem $LLVM_DIR/lib/clang/11.0.0/include/.. -isystem /opt/rocm/include -nogpulib --cuda-device-only -x hip $tmp/hip_pch.h -E >$tmp/pch.cui

cat $tmp/hip_macros.h >> $tmp/pch.cui

$LLVM_DIR/bin/clang -cc1 -O3 -emit-pch -triple amdgcn-amd-amdhsa -aux-triple x86_64-unknown-linux-gnu -fcuda-is-device -std=c++17 -fgnuc-version=4.2.1 -o $tmp/hip.pch -x hip-cpp-output - <$tmp/pch.cui

$LLVM_DIR/bin/llvm-mc -o hip_pch.o $tmp/hip_pch.mcin --filetype=obj

rm -rf $tmp
