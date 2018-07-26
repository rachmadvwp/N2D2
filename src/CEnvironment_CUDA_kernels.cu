/*
    (C) Copyright 2016 CEA LIST. All Rights Reserved.
    Contributor(s): Johannes THIELE (johannes.thiele@cea.fr)
                    Olivier BICHLER (olivier.bichler@cea.fr)

    This software is governed by the CeCILL-C license under French law and
    abiding by the rules of distribution of free software.  You can  use,
    modify and/ or redistribute the software under the terms of the CeCILL-C
    license as circulated by CEA, CNRS and INRIA at the following URL
    "http://www.cecill.info".

    As a counterpart to the access to the source code and  rights to copy,
    modify and redistribute granted by the license, users are provided only
    with a limited warranty  and the software's author,  the holder of the
    economic rights,  and the successive licensors  have only  limited
    liability.

    The fact that you are presently reading this means that you have had
    knowledge of the CeCILL-C license and that you accept its terms.
*/


#include "CEnvironment_CUDA_kernels.hpp"

//#include "cuPrintf.cu"
#include <stdio.h>



__global__ void cudaGenerateInitialSpikes_kernel(float * data,
                                            unsigned long long int * nextEventTime,
                                            char * nextEventType,
                                            unsigned int inputDimX,
                                            unsigned int inputDimY,
                                            unsigned int inputDimZ,
                                            unsigned long long int start,
                                            unsigned long long int stop,
                                            float discardedLateStimuli,
                                            unsigned int stimulusType,
                                            unsigned long long int periodMeanMin,
                                            unsigned long long int periodMeanMax,
                                            float periodRelStdDev,
                                            unsigned long long int periodMin,
                                            curandState * state)
{
    const unsigned int inputStride = blockDim.x;
    const unsigned int inputSize = inputDimX * inputDimY * inputDimZ;
    const unsigned int batchOffset = blockIdx.x * inputSize;

    // Set local state for performance
    curandState local_state = state[threadIdx.x + blockIdx.x * blockDim.x];

    for (unsigned int idx = threadIdx.x; idx < inputSize; idx += inputStride) {

        float value = data[idx + batchOffset];

        unsigned long long int eventTime = nextEventTime[idx + batchOffset];
        char eventType = nextEventType[idx + batchOffset];

        /// Include SpikeGenerator::nextEvent in the kernel
        const double delay = 1.0 - fabsf(value);

        // TODO: Check if singleBurst is really working properly
        if (delay <= discardedLateStimuli) {
            // SingleBurst
            if (stimulusType == 0) {
                if (eventType == 0) {
                    // High pixel values spike earlier
                    //const double transformDelay = 1.0-fabsf(value)*fabsf(value)*fabsf(value);

                    const unsigned long long int t =
                    (unsigned long long int )(start + delay
                                              * (stop - start));
                    eventTime = t;
                    eventType = 1;
                }
                else {
                    eventTime = 0;
                    eventType = 0;
                }
            }
            else {

                const float freqMeanMax = 1.0 / periodMeanMin;
                const float freqMeanMin = 1.0 / periodMeanMax;
                // value = 0 => most significant => maximal frequency (or minimal
                // period)
                const unsigned long long int  periodMean =
                    (unsigned long long int )(1.0 / (freqMeanMax +
                    (freqMeanMin - freqMeanMax) * delay));

                unsigned long long int t = eventTime;
                unsigned long long int dt = 0;


                // Poissonian
                if (stimulusType == 3){
                    dt = (unsigned long long int)
                            (-logf(curand_uniform(&local_state))*periodMean);
                }
                else {
                    dt = (unsigned long long int) (curand_normal(&local_state) *
                        (periodMean * periodRelStdDev)+periodMean);
                    // JitteredPeriodic
                    if (stimulusType == 2 && (eventType == 0)){

                        dt *= curand_uniform(&local_state);
                    }
                }

                if (t > start && dt < periodMin) {
                    dt = periodMin;
                }

                t += dt;

                if (t < stop) {
                    eventTime = t;
                    eventType = 1;
                }
                else {
                    eventTime = 0;
                    eventType = 0;
                }
            }
            nextEventTime[idx + batchOffset] = eventTime;
            nextEventType[idx + batchOffset] = eventType;
        }

        /// End SpikeGenerator::nextEvent

    }

    // Save current state in global memory between kernel launches
    state[threadIdx.x + blockIdx.x * blockDim.x] = local_state;

}


__global__ void cudaGenerateSpikes_kernel(float * data,
                                            char * tickData,
                                            char * tickOutputs,
                                            unsigned long long int * nextEventTime,
                                            char * nextEventType,
                                            unsigned int inputDimX,
                                            unsigned int inputDimY,
                                            unsigned int inputDimZ,
                                            unsigned long long int timestamp,
                                            unsigned long long int start,
                                            unsigned long long int stop,
                                            float discardedLateStimuli,
                                            unsigned int stimulusType,
                                            unsigned long long int periodMeanMin,
                                            unsigned long long int periodMeanMax,
                                            float periodRelStdDev,
                                            unsigned long long int periodMin,
                                            unsigned int nbSubStimuli,
                                            unsigned int subStimulus,
                                            curandState * state)
{
    const unsigned int inputStride = blockDim.x;
    const unsigned int inputSize = inputDimX * inputDimY * inputDimZ;
    const unsigned int inputSizeOutputs = inputDimX * inputDimY * inputDimZ * nbSubStimuli;
    const unsigned int batchOffset = blockIdx.x * inputSize;
    const unsigned int batchOffsetOutputs = blockIdx.x * inputSizeOutputs;

    // Set local state for performance
    curandState local_state = state[threadIdx.x + blockIdx.x * blockDim.x];

    for (unsigned int idx = threadIdx.x; idx < inputSize; idx += inputStride) {

        float value = data[idx + batchOffset];

        if (nextEventType[idx + batchOffset] != 0 &&
        nextEventTime[idx + batchOffset] <= timestamp) {
            tickData[idx + batchOffset] = nextEventType[idx + batchOffset];
            tickOutputs[idx + subStimulus * inputSize + batchOffsetOutputs] =
                nextEventType[idx + batchOffset];
            unsigned long long int eventTime;
            char eventType;

            // This loops creates the next event
            for (unsigned int k = 0; nextEventType[idx + batchOffset] != 0
            && nextEventTime[idx + batchOffset] <= timestamp; ++k) {
                // k>1 if the next event is a spike and still in this time window

                eventTime = nextEventTime[idx + batchOffset];
                eventType = nextEventType[idx + batchOffset];

                /// Include SpikeGenerator::nextEvent in the kernel
                const float delay = 1.0 - fabsf(value);

                if (delay <= discardedLateStimuli) {
                    // SingleBurst
                    if (stimulusType == 0) {
                        if (eventType == 0) {
                            // High pixel values spike earlier
                            const unsigned long long int t =
                            (unsigned long long int )(start + delay
                                                      * (stop - start));
                            eventTime = t;
                            eventType = 1;
                        }
                        else {
                            eventTime = 0;
                            eventType = 0;
                        }
                    }
                    else {

                        const float freqMeanMax = 1.0 / periodMeanMin;
                        const float freqMeanMin = 1.0 / periodMeanMax;
                        // value = 0 => most significant => maximal frequency (or minimal
                        // period)
                        const unsigned long long int  periodMean =
                            (unsigned long long int)(1.0 / (freqMeanMax +
                            (freqMeanMin - freqMeanMax) * delay));

                        unsigned long long int t = eventTime;
                        unsigned long long int dt = 0;


                        // Poissonian
                        if (stimulusType == 3){
                            dt = (unsigned long long int)
                                    (-logf(curand_uniform(&local_state))*periodMean);
                        }
                        else {
                            dt = (unsigned long long int) (curand_normal(&local_state) *
                                (periodMean * periodRelStdDev)+periodMean);
                            // JitteredPeriodic
                            if (stimulusType == 2 && (eventType == 0)){

                                dt *= curand_uniform(&local_state);
                            }

                        }

                        if (t > start && dt < periodMin) {
                            dt = periodMin;
                        }

                        t += dt;

                        if (t < stop) {
                            eventTime = t;
                            eventType = 1;
                        }

                        else {
                            eventTime = 0;
                            eventType = 0;
                        }
                    }
                    nextEventTime[idx + batchOffset] = eventTime;
                    nextEventType[idx + batchOffset] = eventType;
                }

                /// End SpikeGenerator::nextEvent
            }
        }
        else {
            tickData[idx + batchOffset] = 0;
            tickOutputs[idx + subStimulus * inputSize + batchOffsetOutputs] = 0;
        }
    }

    // Save current state in global memory between kernel launches
    state[threadIdx.x + blockIdx.x * blockDim.x] = local_state;

}

__global__ void cudaSetupRng_kernel(curandState * state, unsigned int seed)
{
    int id = threadIdx.x + blockIdx.x * blockDim.x;
    // Each thread gets the same seed but a different sequence number
    curand_init(seed, id, 0, &state[id]);
}

void N2D2::cudaGenerateInitialSpikes(float * data,
                                unsigned long long int * nextEventTime,
                                char * nextEventType,
                                unsigned int inputDimX,
                                unsigned int inputDimY,
                                unsigned int inputDimZ,
                                unsigned long long int start,
                                unsigned long long int stop,
                                float discardedLateStimuli,
                                unsigned int stimulusType,
                                unsigned long long int periodMeanMin,
                                unsigned long long int periodMeanMax,
                                float periodRelStdDev,
                                unsigned long long int periodMin,
                                unsigned int nbBatches,
                                curandState * state)
{


    cudaGenerateInitialSpikes_kernel <<<nbBatches, 16>>>
                                (data,
                                nextEventTime,
                                nextEventType,
                                inputDimX,
                                inputDimY,
                                inputDimZ,
                                start,
                                stop,
                                discardedLateStimuli,
                                stimulusType,
                                periodMeanMin,
                                periodMeanMax,
                                periodRelStdDev,
                                periodMin,
                                state);
}



void N2D2::cudaGenerateSpikes(float * data,
                                char * tickData,
                                char * tickOutputs,
                                unsigned long long int * nextEventTime,
                                char * nextEventType,
                                unsigned int inputDimX,
                                unsigned int inputDimY,
                                unsigned int inputDimZ,
                                unsigned long long int timestamp,
                                unsigned long long int start,
                                unsigned long long int stop,
                                float discardedLateStimuli,
                                unsigned int stimulusType,
                                unsigned long long int periodMeanMin,
                                unsigned long long int periodMeanMax,
                                float periodRelStdDev,
                                unsigned long long int periodMin,
                                unsigned int nbSubStimuli,
                                unsigned int subStimulus,
                                unsigned int nbBatches,
                                curandState * state)
{


    cudaGenerateSpikes_kernel <<<nbBatches, 16>>>
                                (data,
                                tickData,
                                tickOutputs,
                                nextEventTime,
                                nextEventType,
                                inputDimX,
                                inputDimY,
                                inputDimZ,
                                timestamp,
                                start,
                                stop,
                                discardedLateStimuli,
                                stimulusType,
                                periodMeanMin,
                                periodMeanMax,
                                periodRelStdDev,
                                periodMin,
                                nbSubStimuli,
                                subStimulus,
                                state);
}

void N2D2::cudaSetupRng(curandState *state,
                        unsigned int seed,
                        unsigned int nbBatches)
{
    cudaSetupRng_kernel<<<nbBatches, 16>>>(state, seed);
}




