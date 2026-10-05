
#ifndef HELPERS_H
#define HELPERS_H

#include "layer0.h"
#include "layer1_uint32.h"
#include "samples_bnn.h"

void add1d(const int32_t a[], const int32_t b[], int32_t out[], int n);
void zeros1d(int32_t arr[], int n);
void ste_sign(int32_t arr[], int n, int32_t zero_value);
int popcount32(int32_t x);
void neuron0(int32_t x[no_samples][ACTIVATIONS0], int w[ACTIVATIONS0], int32_t yp[no_samples], int N, int use_ste_sign);
void neuron1(uint32_t x[no_samples][ACTIVATIONS1_PACKED], uint32_t w[ACTIVATIONS1_PACKED], int32_t yp[no_samples], int N, int use_ste_sign, int prev_N);
void dense0(int32_t x[no_samples][ACTIVATIONS0], int w[][ACTIVATIONS0],
           int32_t res[][NEURONS0], int nunit, int N, int use_ste_sign);
void dense1(uint32_t x[no_samples][ACTIVATIONS1_PACKED], uint32_t w[][ACTIVATIONS1_PACKED], int32_t res[][NEURONS1], int nunit, int N, int use_ste_sign, int prev_N);
void argmax(int32_t x[][NEURONS1], int32_t labels[], int samples, int N);
int pack_bits(int32_t yout[][NEURONS0], uint32_t packed[][ACTIVATIONS1_PACKED], int NO_SAMPLES);

#endif