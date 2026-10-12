#pragma once
// PROTOTYPE (sharpfive #15): generated from the brief "tape saturation with a tilt EQ".
// Headless DSP, no custom editor — Logic's generic Controls view is the UI.
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_dsp/juce_dsp.h>

class TapeTiltAudioProcessor : public juce::AudioProcessor
{
public:
    TapeTiltAudioProcessor();
    ~TapeTiltAudioProcessor() override = default;

    void prepareToPlay (double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock (juce::AudioBuffer<float>&, juce::MidiBuffer&) override;
    bool isBusesLayoutSupported (const BusesLayout& layouts) const override;

    juce::AudioProcessorEditor* createEditor() override { return nullptr; }
    bool hasEditor() const override { return false; }

    const juce::String getName() const override { return "TapeTilt"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram (int) override {}
    const juce::String getProgramName (int) override { return {}; }
    void changeProgramName (int, const juce::String&) override {}

    void getStateInformation (juce::MemoryBlock&) override;
    void setStateInformation (const void*, int) override;

    juce::AudioProcessorValueTreeState& getParameters() { return parameters; }

private:
    using Filter    = juce::dsp::IIR::Filter<float>;
    using Coeffs    = juce::dsp::IIR::Coefficients<float>;
    using StereoIIR = juce::dsp::ProcessorDuplicator<Filter, Coeffs>;

    void updateTilt (float tiltDb, float centreHz);

    double currentSampleRate = 44100.0;

    juce::dsp::Oversampling<float> oversampling { 2, 1,
        juce::dsp::Oversampling<float>::filterHalfBandFIREquiripple, true };
    juce::dsp::Gain<float> driveGain;                 // pre-saturation, runs at 2x
    juce::dsp::WaveShaper<float> shaper;              // tanh tape curve
    StereoIIR lowShelf, highShelf;                    // tilt = opposing shelves
    juce::dsp::Gain<float> outputGain;
    juce::dsp::DryWetMixer<float> dryWet;

    float lastTilt = 1.0e9f, lastCentre = 1.0e9f;

    juce::AudioProcessorValueTreeState parameters;    // after the DSP members
    static juce::AudioProcessorValueTreeState::ParameterLayout createParameterLayout();

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (TapeTiltAudioProcessor)
};
