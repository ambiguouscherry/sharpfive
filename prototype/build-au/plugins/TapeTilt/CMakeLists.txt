project(TapeTilt VERSION 1.1.0)

set(PRODUCT_NAME "TapeTilt")

juce_add_plugin(TapeTilt
    COMPANY_NAME "Sharpfive"
    PLUGIN_MANUFACTURER_CODE Shfv
    PLUGIN_CODE Tptl
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    COPY_PLUGIN_AFTER_BUILD FALSE
    FORMATS VST3 AU
    PRODUCT_NAME "${PRODUCT_NAME}")

target_sources(TapeTilt
    PRIVATE
        Source/PluginProcessor.cpp)

target_compile_definitions(TapeTilt
    PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0)

target_link_libraries(TapeTilt
    PRIVATE
        juce::juce_audio_utils
        juce::juce_dsp
    PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags)

# CRITICAL: must come after target_link_libraries()
juce_generate_juce_header(TapeTilt)
