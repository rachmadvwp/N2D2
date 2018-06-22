/*
    (C) Copyright 2013 CEA LIST. All Rights Reserved.
    Contributor(s): Olivier BICHLER (olivier.bichler@cea.fr)

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

#ifndef N2D2_CONVCELL_FRAME_H
#define N2D2_CONVCELL_FRAME_H

#include "Cell_Frame.hpp"
#include "ConvCell.hpp"
#include "ConvCell_Frame_Kernels.hpp"
#include "Solver/SGDSolver_Frame.hpp"

namespace N2D2 {
class ConvCell_Frame : public virtual ConvCell, public Cell_Frame {
public:
    ConvCell_Frame(const std::string& name,
                   const std::vector<unsigned int>& kernelDims,
                   unsigned int nbOutputs,
                   const std::vector<unsigned int>& subSampleDims
                        = std::vector<unsigned int>(2, 1U),
                   const std::vector<unsigned int>& strideDims
                        = std::vector<unsigned int>(2, 1U),
                   const std::vector<int>& paddingDims
                        = std::vector<int>(2, 0),
                   const std::shared_ptr<Activation<Float_T> >& activation
                        = std::make_shared<TanhActivation_Frame<Float_T> >());
    static std::shared_ptr<ConvCell> create(Network& /*net*/,
             const std::string& name,
             const std::vector<unsigned int>& kernelDims,
             unsigned int nbOutputs,
             const std::vector<unsigned int>& subSampleDims
                    = std::vector<unsigned int>(2, 1U),
             const std::vector<unsigned int>& strideDims
                    = std::vector<unsigned int>(2, 1U),
             const std::vector<int>& paddingDims = std::vector<int>(2, 0),
             const std::shared_ptr<Activation<Float_T> >& activation
                    = std::make_shared<TanhActivation_Frame<Float_T> >())
    {
        return std::make_shared<ConvCell_Frame>(name,
                                                kernelDims,
                                                nbOutputs,
                                                subSampleDims,
                                                strideDims,
                                                paddingDims,
                                                activation);
    }

    virtual void initialize();
    virtual void propagate(bool inference = false);
    virtual void backPropagate();
    virtual void update();
    inline Tensor<Float_T> getWeight(unsigned int output,
                                     unsigned int channel) const
    {
        unsigned int tensorChannel;
        const Tensor<Float_T>& sharedSynapses
            = mSharedSynapses.getTensor(channel, &tensorChannel);
        return sharedSynapses[output][channel - tensorChannel];
    };
    inline Float_T getBias(unsigned int output) const
    {
        return (*mBias)(output);
    };
    inline Interface<Float_T>* getWeights()
    {
        return &mSharedSynapses;
    };
    void setWeights(unsigned int k,
                    Interface<Float_T>* weights,
                    unsigned int offset);
    inline std::shared_ptr<Tensor<Float_T> > getBiases()
    {
        return mBias;
    };
    inline void setBiases(const std::shared_ptr<Tensor<Float_T> >& biases)
    {
        mBias = biases;
    }
    void checkGradient(double epsilon = 1.0e-4, double maxError = 1.0e-6);
    void saveFreeParameters(const std::string& fileName) const;
    void loadFreeParameters(const std::string& fileName,
                            bool ignoreNotExists = false);
    virtual ~ConvCell_Frame();

protected:
    inline void setWeight(unsigned int output,
                          unsigned int channel,
                          const Tensor<Float_T>& value)
    {
        unsigned int tensorChannel;
        Tensor<Float_T>& sharedSynapses
            = mSharedSynapses.getTensor(channel, &tensorChannel);
        sharedSynapses[output][channel - tensorChannel] = value;
    }
    inline void setBias(unsigned int output, Float_T value)
    {
        (*mBias)(output) = value;
    };

    // Internal
    std::vector<std::shared_ptr<Solver<Float_T> > > mWeightsSolvers;
    Interface<Float_T> mSharedSynapses;
    std::map<unsigned int,
        std::pair<Interface<Float_T>*, unsigned int> > mExtSharedSynapses;
    std::shared_ptr<Tensor<Float_T> > mBias;
    Interface<Float_T> mDiffSharedSynapses;
    Tensor<Float_T> mDiffBias;
    ConvCell_Frame_Kernels::Descriptor mConvDesc;

private:
    static Registrar<ConvCell> mRegistrar;
};
}

#endif // N2D2_CONVCELL_FRAME_H
