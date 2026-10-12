#include "PluginProcessor.h"

juce::AudioProcessorValueTreeState::ParameterLayout
TapeTiltAudioProcessor::createParameterLayout()
{
    juce::AudioProcessorValueTreeState::ParameterLayout layout;

    layout.add (std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID { "drive", 1 }, "Drive",
        juce::NormalisableRange<float> (0.0f, 24.0f, 0.1f), 6.0f, "dB"));

    layout.add (std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID { "tilt", 1 }, "Tilt",
        juce::NormalisableRange<float> (-6.0f, 6.0f, 0.1f), 0.0f, "dB"));

    layout.add (std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID { "tiltFreq", 1 }, "Tilt Freq",
        juce::NormalisableRange<float> (200.0f, 2000.0f, 1.0f, 0.5f), 800.0f, "Hz"));

    layout.add (std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID { "output", 1 }, "Output",
        juce::NormalisableRange<float> (-24.0f, 12.0f, 0.1f), 0.0f, "dB"));

    layout.add (std::make_unique<juce::AudioParameterFloat>(
        juce::ParameterID { "mix", 1 }, "Mix",
        juce::NormalisableRange<float> (0.0f, 100.0f, 1.0f), 100.0f, "%"));

    return layout;
}

TapeTiltAudioProcessor::TapeTiltAudioProcessor()
    : AudioProcessor (BusesProperties()
                          .withInput  ("Input",  juce::AudioChannelSet::stereo(), true)
                          .withOutput ("Output", juce::AudioChannelSet::stereo(), true))
    , parameters (*this, nullptr, "Parameters", createParameterLayout())
{
    // Tape-ish curve: tanh with a touch of even-harmonic asymmetry via a square term.
    shaper.functionToUse = [] (float x) { return std::tanh (x + 0.05f * x * x); };
}

bool TapeTiltAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    const auto& in  = layouts.getMainInputChannelSet();
    const auto& out = layouts.getMainOutputChannelSet();
    if (in != out) return false;
    return out == juce::AudioChannelSet::mono() || out == juce::AudioChannelSet::stereo();
}

void TapeTiltAudioProcessor::updateTilt (float tiltDb, float centreHz)
{
    if (tiltDb == lastTilt && centreHz == lastCentre) return;
    lastTilt = tiltDb; lastCentre = centreHz;

    const float half = tiltDb * 0.5f;
    *lowShelf.state  = *Coeffs::makeLowShelf  (currentSampleRate, centreHz, 0.707f,
                                               juce::Decibels::decibelsToGain (-half));
    *highShelf.state = *Coeffs::makeHighShelf (currentSampleRate, centreHz, 0.707f,
                                               juce::Decibels::decibelsToGain ( half));
}

void TapeTiltAudioProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    currentSampleRate = sampleRate;

    juce::dsp::ProcessSpec spec;
    spec.sampleRate       = sampleRate;
    spec.maximumBlockSize = static_cast<juce::uint32> (samplesPerBlock);
    spec.numChannels      = static_cast<juce::uint32> (getTotalNumOutputChannels());

    oversampling.reset();
    oversampling.initProcessing (static_cast<size_t> (samplesPerBlock));

    juce::dsp::ProcessSpec osSpec = spec;
    osSpec.sampleRate       = sampleRate * 2.0;
    osSpec.maximumBlockSize = static_cast<juce::uint32> (samplesPerBlock * 2);

    driveGain.prepare (osSpec);  driveGain.reset();
    driveGain.setRampDurationSeconds (0.02);
    shaper.prepare (osSpec);     shaper.reset();

    lowShelf.prepare (spec);     lowShelf.reset();
    highShelf.prepare (spec);    highShelf.reset();
    lastTilt = lastCentre = 1.0e9f;   // force coefficient refresh at the new rate

    dcBlock.prepare (spec);      dcBlock.reset();
    *dcBlock.state = *Coeffs::makeFirstOrderHighPass (sampleRate, 5.0f);

    outputGain.prepare (spec);   outputGain.reset();
    outputGain.setRampDurationSeconds (0.02);

    dryWet.prepare (spec);       dryWet.reset();
    dryWet.setMixingRule (juce::dsp::DryWetMixingRule::linear);
    dryWet.setWetLatency (static_cast<float> (oversampling.getLatencyInSamples()));

    setLatencySamples (static_cast<int> (std::ceil (oversampling.getLatencyInSamples())));
}

void TapeTiltAudioProcessor::releaseResources() {}

void TapeTiltAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer,
                                           juce::MidiBuffer& midiMessages)
{
    juce::ScopedNoDenormals noDenormals;
    juce::ignoreUnused (midiMessages);

    for (int i = getTotalNumInputChannels(); i < getTotalNumOutputChannels(); ++i)
        buffer.clear (i, 0, buffer.getNumSamples());

    const float drive  = parameters.getRawParameterValue ("drive")->load();
    const float tilt   = parameters.getRawParameterValue ("tilt")->load();
    const float centre = parameters.getRawParameterValue ("tiltFreq")->load();
    const float outDb  = parameters.getRawParameterValue ("output")->load();
    const float mix    = parameters.getRawParameterValue ("mix")->load() * 0.01f;

    juce::dsp::AudioBlock<float> block (buffer);
    dryWet.setWetMixProportion (mix);
    dryWet.pushDrySamples (block);

    // Saturate at 2x: drive in, tanh, then pull the full drive back out so the stage sits near unity
    // at its default. (1.0.0 pulled back only half: the tap measured wet +2.7 dB over bypass, #16.)
    auto osBlock = oversampling.processSamplesUp (block);
    driveGain.setGainDecibels (drive);
    juce::dsp::ProcessContextReplacing<float> osCtx (osBlock);
    driveGain.process (osCtx);
    shaper.process (osCtx);
    osBlock.multiplyBy (juce::Decibels::decibelsToGain (-drive));
    oversampling.processSamplesDown (block);

    updateTilt (tilt, centre);
    juce::dsp::ProcessContextReplacing<float> ctx (block);
    lowShelf.process (ctx);
    highShelf.process (ctx);
    dcBlock.process (ctx);   // the asymmetric curve rectifies a little; measured +6 dB of DC over dry (#16)

    outputGain.setGainDecibels (outDb);
    outputGain.process (ctx);

    dryWet.mixWetSamples (block);
}

void TapeTiltAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    auto state = parameters.copyState();
    std::unique_ptr<juce::XmlElement> xml (state.createXml());
    copyXmlToBinary (*xml, destData);
}

void TapeTiltAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    std::unique_ptr<juce::XmlElement> xmlState (getXmlFromBinary (data, sizeInBytes));

    if (xmlState != nullptr && xmlState->hasTagName (parameters.state.getType()))
        parameters.replaceState (juce::ValueTree::fromXml (*xmlState));
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new TapeTiltAudioProcessor();
}
