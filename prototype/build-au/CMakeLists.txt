cmake_minimum_required(VERSION 3.22)

set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13" CACHE STRING "Minimum macOS deployment version")

project(Sharpfive VERSION 1.0.0)

# Locate JUCE once at root.
# Override explicitly with: cmake -B build -DJUCE_DIR=/path/to/JUCE
if(NOT JUCE_DIR)
    foreach(candidate
            "${CMAKE_CURRENT_SOURCE_DIR}/JUCE"
            "$ENV{HOME}/JUCE"
            "/Applications/JUCE"
            "/usr/local/JUCE")
        if(EXISTS "${candidate}/CMakeLists.txt")
            set(JUCE_DIR "${candidate}")
            break()
        endif()
    endforeach()
endif()

if(NOT JUCE_DIR OR NOT EXISTS "${JUCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "JUCE not found. Checked ./JUCE, $ENV{HOME}/JUCE, /Applications/JUCE, /usr/local/JUCE.\n"
        "Pass the path explicitly: cmake -B build -DJUCE_DIR=/path/to/JUCE")
endif()

message(STATUS "Using JUCE from: ${JUCE_DIR}")
add_subdirectory(${JUCE_DIR} JUCE)

# Auto-discover plugins
file(GLOB PLUGIN_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/plugins/*")
foreach(PLUGIN_DIR ${PLUGIN_DIRS})
    if(IS_DIRECTORY ${PLUGIN_DIR} AND EXISTS "${PLUGIN_DIR}/CMakeLists.txt")
        add_subdirectory(${PLUGIN_DIR})
    endif()
endforeach()
